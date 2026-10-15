import Foundation

private extension LocationMapViewModel {
    static let consentVersion = "location-sharing-v1"
}

extension LocationMapViewModel {
    func setSharingEnabled(_ enabled: Bool) async {
        refreshAuthorizationState()
        guard enabled != sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginOperation(.sharingChange)
        else {
            return
        }

        let operationIdentity = identity
        defer { finishOperation(operationID) }
        // Read before the capture, which may show the system prompt and change it.
        let permissionWasUndecided = authorizationState == .notDetermined

        let previousValue = sharingEnabled
        showSharingChoice(enabled)

        do {
            try await persistSharingChange(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                enabled: enabled,
                operationID: operationID,
                operationIdentity: operationIdentity
            )

            await syncAfterLocalChange()
            try requireCurrent(operationID, identity: operationIdentity)
            await reload()
        } catch LocationOperationAbort.superseded {
            return
        } catch {
            await restoreSharingChange(
                previousValue: previousValue,
                operationIdentity: operationIdentity,
                permissionWasUndecided: permissionWasUndecided,
                error: error
            )
        }
    }

    private func enqueueLocationPreference(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        source: LocationSharingSource
    ) async throws {
        let operation = operationProvider.makeOperation()
        let payload = LocationSharingOperationPayload(
            coupleID: coupleID,
            isEnabled: isEnabled,
            consentVersion: isEnabled ? Self.consentVersion : nil,
            source: source
        )
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .updateLocationSharingPreference,
                idempotencyScope: [
                    "location-preference",
                    coupleID.uuidString.lowercased(),
                    operation.id.uuidString.lowercased(),
                ].joined(separator: ":"),
                requestData: try encoder.encode(payload)
            )
        )
    }

    private func persistSharingChange(
        ownerUserID: UUID,
        coupleID: UUID,
        enabled: Bool,
        operationID: UUID,
        operationIdentity: LocationIdentity
    ) async throws {
        let ensureCurrent = { [self] in
            try requireCurrent(operationID, identity: operationIdentity)
        }
        let capturedLocation = try await captureLocationForSharing(enabled: enabled)
        try ensureCurrent()

        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: enabled,
            updatedAt: Date()
        )
        try ensureCurrent()

        try await enqueueLocationPreference(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: enabled,
            source: .settingsToggle
        )
        try ensureCurrent()

        if let capturedLocation {
            try await saveFirstFix(
                capturedLocation,
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                ensureCurrent: ensureCurrent
            )
        } else {
            try? await ownLocationStore.delete(ownerUserID: ownerUserID, coupleID: coupleID)
            await dropQueuedLocationUploads(
                ownerUserID: ownerUserID,
                keeping: nil,
                reason: "cancelled because location sharing was turned off"
            )
        }
        try ensureCurrent()
    }

    /// The fix to send along with turning sharing on. Nil when sharing is turned off,
    /// or when no fix is available right now.
    private func captureLocationForSharing(enabled: Bool) async throws -> LocationPoint? {
        guard enabled else { return nil }
        do {
            return try await captureCurrentLocation()
        } catch ForegroundLocationCaptureError.unavailable
            where locationCapture.authorizationState == .authorized {
            // The durable sharing choice does not depend on one GPS fix.
            // A later foreground refresh can fill in the current location,
            // and the map card offers a retry meanwhile.
            show(.locationUnavailable)
            return nil
        }
    }

    private func saveFirstFix(
        _ location: LocationPoint,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws {
        do {
            try await saveAndEnqueueOwnLocation(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: location,
                source: .settingsToggle,
                ensureCurrent: ensureCurrent
            )
        } catch LocationOperationAbort.superseded {
            throw LocationOperationAbort.superseded
        } catch {
            // The preference is already safely cached and queued. Keep the
            // user's choice even if saving this first fix fails; a later
            // foreground refresh can try the latest location again.
            try ensureCurrent()
            show(.saveFailed)
        }
    }

    private func restoreSharingChange(
        previousValue: Bool,
        operationIdentity: LocationIdentity,
        permissionWasUndecided: Bool,
        error: any Error
    ) async {
        guard identity == operationIdentity,
              let ownerUserID = operationIdentity.currentUserID,
              let coupleID = operationIdentity.coupleID
        else { return }
        refreshAuthorizationState()
        restoreSharingValue(previousValue)
        // Nothing was queued for this value, so it is not waiting on the server.
        try? await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: previousValue,
            updatedAt: Date(),
            isPendingConfirmation: false
        )
        guard identity == operationIdentity else { return }
        // Tapping "Don't Allow" on the system prompt is a choice, not an
        // error. The map card already shows how to turn location on later.
        let declinedSystemPrompt = permissionWasUndecided
            && (error as? ForegroundLocationCaptureError) == .authorizationDenied
        if !declinedSystemPrompt {
            show(notice(for: error))
        }
        await reload()
    }
}
