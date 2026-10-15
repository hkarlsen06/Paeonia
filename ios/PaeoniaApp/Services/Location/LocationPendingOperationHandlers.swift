import Foundation

struct LocationSharingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateLocationSharingPreference

    private let gateway: any LocationGateway
    private let visibilityStore: any LocationVisibilitySnapshotPersisting

    init(
        gateway: any LocationGateway,
        visibilityStore: any LocationVisibilitySnapshotPersisting
    ) {
        self.gateway = gateway
        self.visibilityStore = visibilityStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing location preference payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(LocationSharingOperationPayload.self, from: requestData)
        let response = try await gateway.updateLocationSharingPreference(
            payload: payload,
            operation: operation.operation
        )
        // A newer choice may be waiting behind this one. Its own answer is the
        // one that should reach the local store.
        let otherChoicesPending = try await context.pendingOperationStore.inFlightOperations(
            ownerUserID: operation.ownerUserID,
            kind: .updateLocationSharingPreference
        ).contains { $0.operation.id != operation.operation.id }
        try await visibilityStore.confirmViewerSharing(
            ownerUserID: response?.userID ?? operation.ownerUserID,
            coupleID: response?.coupleID ?? payload.coupleID,
            isEnabled: response?.isEnabled ?? payload.isEnabled,
            updatedAt: response?.updatedAt ?? Date(),
            otherChoicesPending: otherChoicesPending
        )

        return .succeeded
    }
}

struct LatestLocationPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateLatestPartnerLocation

    private let gateway: any LocationGateway
    private let ownLocationStore: any OwnLocationSnapshotPersisting

    init(
        gateway: any LocationGateway,
        ownLocationStore: any OwnLocationSnapshotPersisting
    ) {
        self.gateway = gateway
        self.ownLocationStore = ownLocationStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing latest location payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(
            LatestPartnerLocationOperationPayload.self,
            from: requestData
        )

        do {
            if let response = try await gateway.updateLatestPartnerLocation(
                payload: payload,
                operation: operation.operation
            ) {
                try await storeConfirmedLocation(response, payload: payload, operation: operation)
            } else {
                try await clearPendingOperation(operation, payload: payload)
            }
            return .succeeded
        } catch where Self.isPermanentRejection(error) {
            // Retrying cannot help: sharing is off on the server, or the location
            // is out of range. Retrying forever would also keep a location queued
            // after the user stopped sharing.
            return .terminalFailure("Location update rejected: \(error)")
        }
    }

    /// Keeps the server's answer as our own location, unless a newer position is
    /// already stored.
    private func storeConfirmedLocation(
        _ response: LatestPartnerLocationUpdateResponse,
        payload: LatestPartnerLocationOperationPayload,
        operation: PendingSyncOperationSnapshot
    ) async throws {
        let existing = try await ownLocationStore.load(
            ownerUserID: response.userID,
            coupleID: response.coupleID
        )
        if let existing, existing.location.capturedAt > response.capturedAt {
            try await clearPendingOperation(operation, payload: payload)
            return
        }

        try await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: response.userID,
                coupleID: response.coupleID,
                location: LocationPoint(
                    latitude: response.latitude,
                    longitude: response.longitude,
                    accuracyMeters: response.accuracyMeters,
                    capturedAt: response.capturedAt,
                    updatedAt: response.updatedAt
                ),
                source: payload.source,
                pendingOperationID: nil,
                updatedAt: response.updatedAt
            )
        )
    }

    private func clearPendingOperation(
        _ operation: PendingSyncOperationSnapshot,
        payload: LatestPartnerLocationOperationPayload
    ) async throws {
        try await ownLocationStore.clearPendingOperation(
            ownerUserID: operation.ownerUserID,
            coupleID: payload.coupleID,
            operationID: operation.operation.id
        )
    }

    /// The server also answers `42501` for a sign-in it can't see yet and for
    /// access that may come back, so only the "sharing is off" refusal stops it.
    private static func isPermanentRejection(_ error: any Error) -> Bool {
        guard case let .server(code, _) = error as? PaeoniaConvexError else {
            return false
        }
        return code == "23514" || isSharingOffRejection(error)
    }

    /// The server refused because sharing is off for this person.
    static func isSharingOffRejection(_ error: any Error) -> Bool {
        guard case let .server(code, message) = error as? PaeoniaConvexError else {
            return false
        }
        return code == "42501" && message.contains("location sharing must be enabled")
    }
}
