import Foundation

/// Sends one position while Paeonia is closed. It calls the server directly
/// instead of going through the outbox, because the outbox only runs while
/// the app is open. A position that fails to send is dropped: the next move,
/// or opening the app, sends a newer one.
struct BackgroundLocationUploader {
    enum Outcome: Equatable {
        case sent
        /// Too soon after the last sent position, and the phone barely moved.
        case skipped
        /// Sharing is off on this phone or on the server. Updates while
        /// closed should stop.
        case sharingOff
        /// Sharing is paused, on this phone or on the server. Nothing was sent.
        /// The choice for updates while closed stays, since the pause ends by itself.
        case paused
        /// The choice was cleared while this ran, so nothing was sent or saved.
        case cancelled
        case failed
    }

    private let gateway: (any LocationGateway)?
    private let visibilityStore: any LocationVisibilitySnapshotPersisting
    private let ownLocationStore: any OwnLocationSnapshotPersisting
    private let operationProvider: any SyncClientOperationProviding
    private let now: () -> Date

    init(
        gateway: (any LocationGateway)?,
        visibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.visibilityStore = visibilityStore
        self.ownLocationStore = ownLocationStore
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.now = now
    }

    func upload(_ location: LocationPoint, ownerUserID: UUID, coupleID: UUID) async -> Outcome {
        switch await sharingState(ownerUserID: ownerUserID, coupleID: coupleID) {
        case .on?:
            break
        case .off?:
            return .sharingOff
        case .paused?:
            return .paused
        case nil:
            return .failed
        }

        let lastSent = try? await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        guard RoutineLocationThrottle.shouldSend(lastSent: lastSent?.location, current: location, now: now()) else {
            return .skipped
        }
        guard let gateway, !Task.isCancelled else {
            return gateway == nil ? .failed : .cancelled
        }
        return await send(location, through: gateway, ownerUserID: ownerUserID, coupleID: coupleID)
    }

    private func send(
        _ location: LocationPoint,
        through gateway: any LocationGateway,
        ownerUserID: UUID,
        coupleID: UUID
    ) async -> Outcome {
        do {
            let response = try await gateway.updateLatestPartnerLocation(
                payload: LatestPartnerLocationOperationPayload(
                    coupleID: coupleID,
                    location: location,
                    source: .background
                ),
                operation: operationProvider.makeOperation()
            )
            guard !Task.isCancelled else {
                return .cancelled
            }
            await storeSent(location, response: response, ownerUserID: ownerUserID, coupleID: coupleID)
            return .sent
        } catch where LatestLocationPendingOperationHandler.isSharingOffRejection(error) {
            return .sharingOff
        } catch where LatestLocationPendingOperationHandler.isPausedRejection(error) {
            return .paused
        } catch {
            return .failed
        }
    }

    /// Records what the server stored, so the next wake measures from it.
    /// A newer location saved meanwhile, such as from opening the app, wins.
    private func storeSent(
        _ location: LocationPoint,
        response: LatestPartnerLocationUpdateResponse?,
        ownerUserID: UUID,
        coupleID: UUID
    ) async {
        let sentLocation = response.map {
            LocationPoint(
                latitude: $0.latitude,
                longitude: $0.longitude,
                accuracyMeters: $0.accuracyMeters,
                capturedAt: $0.capturedAt,
                updatedAt: $0.updatedAt
            )
        } ?? location
        // Sharing may have been turned off, or local data cleared, while this
        // was sending. Both already removed the stored location.
        guard await sharingState(ownerUserID: ownerUserID, coupleID: coupleID) == .on else {
            return
        }
        // Read right before the save so a newer location from the open app is
        // rarely missed. If one lands in between, its own queued upload stores
        // it again once the server confirms it.
        let stored = try? await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        if let stored, stored.location.capturedAt >= sentLocation.capturedAt {
            return
        }
        try? await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: sentLocation,
                source: .background,
                pendingOperationID: nil,
                updatedAt: response?.updatedAt ?? now()
            )
        )
        // Turning sharing off marks it off before it deletes the location. If
        // that delete ran just before this save, undo the save.
        if await sharingState(ownerUserID: ownerUserID, coupleID: coupleID) != .on {
            try? await ownLocationStore.delete(ownerUserID: ownerUserID, coupleID: coupleID)
        }
    }

    private enum SharingState {
        case on
        case off
        case paused
    }

    /// `nil` when the local store could not be read, which is not the same
    /// as sharing being off. A pause counts until its time on this phone's
    /// clock, so a pause that ended while the app was closed lets the next
    /// move through.
    private func sharingState(ownerUserID: UUID, coupleID: UUID) async -> SharingState? {
        do {
            let visibility = try await visibilityStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
            guard visibility?.viewerSharingEnabled == true else { return .off }
            return visibility?.pausedUntil(at: now()) == nil ? .on : .paused
        } catch {
            return nil
        }
    }
}
