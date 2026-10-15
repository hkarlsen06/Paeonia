import Foundation

extension LocationMapViewModel {
    func refreshOwnLocationIfSharingEnabled(
        source: LocationSharingSource,
        mayPromptForAuthorization: Bool = true
    ) async {
        // Scene activation lands here, so this is also where a permission
        // change made in the Settings app reaches the map card.
        refreshAuthorizationState()
        guard mayPromptForAuthorization || authorizationState == .authorized else {
            return
        }

        guard sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginOperation(.refresh)
        else {
            return
        }

        let operationIdentity = identity
        defer { finishOperation(operationID) }
        let ensureCurrent = { [self] in
            try requireCurrent(operationID, identity: operationIdentity)
        }

        do {
            try await captureAndQueueOwnLocation(
                source: source,
                ownerUserID: currentUserID,
                coupleID: coupleID,
                ensureCurrent: ensureCurrent
            )
        } catch LocationOperationAbort.superseded {
            return
        } catch {
            guard identity == operationIdentity else { return }
            // An automatic refresh on app open must not raise an error banner
            // every time the phone is indoors. The map card shows the state.
            guard source != .foregroundOpen else { return }
            show(notice(for: error))
        }
    }

    /// A position from the live feed while the app is open. It follows the
    /// same rule as a refresh on app open, so standing still sends nothing.
    func submitObservedLocation(_ location: LocationPoint) async {
        refreshAuthorizationState()
        guard sharingEnabled,
              authorizationState == .authorized,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginOperation(.refresh)
        else {
            return
        }

        let operationIdentity = identity
        defer { finishOperation(operationID) }
        // A position that fails to save is fine to miss. The next move sends again.
        try? await queueOwnLocationIfDue(
            location,
            source: .foregroundOpen,
            ownerUserID: currentUserID,
            coupleID: coupleID,
            ensureCurrent: { [self] in try requireCurrent(operationID, identity: operationIdentity) }
        )
    }

    private func captureAndQueueOwnLocation(
        source: LocationSharingSource,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws {
        let location = try await captureCurrentLocation()
        try ensureCurrent()
        try await queueOwnLocationIfDue(
            location,
            source: source,
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            ensureCurrent: ensureCurrent
        )
    }

    private func queueOwnLocationIfDue(
        _ location: LocationPoint,
        source: LocationSharingSource,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws {
        guard try await shouldSendLocation(
            location,
            source: source,
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            ensureCurrent: ensureCurrent
        ) else { return }

        try await saveAndEnqueueOwnLocation(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: location,
            source: source,
            ensureCurrent: ensureCurrent
        )

        await syncAfterLocalChange()
        try ensureCurrent()
        await reload()
    }

    private func shouldSendLocation(
        _ location: LocationPoint,
        source: LocationSharingSource,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws -> Bool {
        // A routine foreground refresh only writes when the fix is stale or the
        // user moved; explicit refreshes always write.
        guard source == .foregroundOpen else { return true }

        let lastSent = (try? await ownLocationStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        ))?.location
        try ensureCurrent()
        return RoutineLocationThrottle.shouldSend(
            lastSent: lastSent,
            current: location,
            now: Date()
        )
    }

    func saveAndEnqueueOwnLocation(
        ownerUserID: UUID,
        coupleID: UUID,
        location: LocationPoint,
        source: LocationSharingSource,
        ensureCurrent: () throws -> Void
    ) async throws {
        let operation = operationProvider.makeOperation()
        let previousSnapshot = try await ownLocationStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        )
        // Checked right before each write, so a refresh that a newer sharing
        // choice replaced never stores or queues a location after an opt-out.
        try ensureCurrent()
        try await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: location,
                source: source,
                pendingOperationID: operation.id,
                updatedAt: Date()
            )
        )

        do {
            try ensureCurrent()
            try await enqueueReplacingOlderLocations(
                latestLocationRequest(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    location: location,
                    source: source,
                    operation: operation
                )
            )
        } catch LocationOperationAbort.superseded {
            // The operation that replaced this one owns the stored state now.
            throw LocationOperationAbort.superseded
        } catch {
            // A fresh snapshot without its matching pending operation would
            // make the foreground throttle believe this location was queued.
            // Restore the last durable state so the next refresh retries.
            if let previousSnapshot {
                try? await ownLocationStore.save(previousSnapshot)
            } else {
                try? await ownLocationStore.delete(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID
                )
            }
            throw error
        }
    }

    /// Queues a location upload and drops older queued ones, but only after
    /// the newer one is safely queued.
    private func enqueueReplacingOlderLocations(_ request: PendingSyncOperationRequest) async throws {
        try await pendingOperationStore.enqueue(request)
        await dropQueuedLocationUploads(
            ownerUserID: request.ownerUserID,
            keeping: request.operation.id,
            reason: "replaced by a newer location"
        )
    }

    private func latestLocationRequest(
        ownerUserID: UUID,
        coupleID: UUID,
        location: LocationPoint,
        source: LocationSharingSource,
        operation: SyncClientOperation
    ) throws -> PendingSyncOperationRequest {
        let payload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: location,
            source: source
        )
        return PendingSyncOperationRequest(
            ownerUserID: ownerUserID,
            operation: operation,
            operationKind: .updateLatestPartnerLocation,
            idempotencyScope: [
                "latest-location",
                coupleID.uuidString.lowercased(),
                operation.id.uuidString.lowercased(),
            ].joined(separator: ":"),
            requestData: try encoder.encode(payload)
        )
    }

    /// Drops queued location uploads that have not started sending, except
    /// `keeping`. Used for two cases. A location queued before an opt-out must
    /// not reach the server after it (the outbox can send it first while the
    /// opt-out waits for a retry). And only the latest position matters, so a
    /// newer location replaces older ones instead of replaying each of them.
    func dropQueuedLocationUploads(ownerUserID: UUID, keeping kept: UUID?, reason: String) async {
        let queued = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        )) ?? []
        for operation in queued where operation.status != .sending && operation.operation.id != kept {
            try? await pendingOperationStore.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: reason,
                at: Date()
            )
        }
    }
}
