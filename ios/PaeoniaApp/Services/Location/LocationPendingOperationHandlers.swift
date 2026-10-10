import Foundation

struct LocationSharingPreferencePendingOperationHandler: PendingSyncOperationHandling {
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

        let payload = try JSONDecoder().decode(LocationSharingPreferenceOperationPayload.self, from: requestData)
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

struct LatestPartnerLocationPendingOperationHandler: PendingSyncOperationHandling {
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

        let payload = try JSONDecoder().decode(LatestPartnerLocationOperationPayload.self, from: requestData)

        do {
            if let response = try await gateway.updateLatestPartnerLocation(
                payload: payload,
                operation: operation.operation
            ) {
                let existing = try await ownLocationStore.load(
                    ownerUserID: response.userID,
                    coupleID: response.coupleID
                )
                if let existing, existing.location.capturedAt > response.capturedAt {
                    try await ownLocationStore.clearPendingOperation(
                        ownerUserID: operation.ownerUserID,
                        coupleID: payload.coupleID,
                        operationID: operation.operation.id
                    )
                    return .succeeded
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
            } else {
                try await ownLocationStore.clearPendingOperation(
                    ownerUserID: operation.ownerUserID,
                    coupleID: payload.coupleID,
                    operationID: operation.operation.id
                )
            }
            return .succeeded
        } catch where Self.isStaleLocationError(error) {
            return .terminalFailure("Stale location update rejected")
        }
    }

    private static func isStaleLocationError(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("stale location update")
            && description.contains("rejected")
    }
}
