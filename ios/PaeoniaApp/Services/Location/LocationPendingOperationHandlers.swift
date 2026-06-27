import Foundation

struct LocationSharingPreferencePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateLocationSharingPreference

    private let gateway: any SupabaseLocationGateway
    private let visibilityStore: any LocationVisibilitySnapshotPersisting

    init(
        gateway: any SupabaseLocationGateway,
        visibilityStore: any LocationVisibilitySnapshotPersisting
    ) {
        self.gateway = gateway
        self.visibilityStore = visibilityStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing location preference payload")
        }

        let payload = try JSONDecoder().decode(LocationSharingPreferenceOperationPayload.self, from: requestData)
        if let response = try await gateway.updateLocationSharingPreference(
            payload: payload,
            operation: operation.operation
        ) {
            try await visibilityStore.setViewerSharingEnabled(
                ownerUserID: response.userID,
                coupleID: response.coupleID,
                isEnabled: response.isEnabled,
                updatedAt: response.updatedAt
            )
        }

        return .succeeded
    }
}

struct LatestPartnerLocationPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateLatestPartnerLocation

    private let gateway: any SupabaseLocationGateway
    private let ownLocationStore: any OwnLocationSnapshotPersisting

    init(
        gateway: any SupabaseLocationGateway,
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
        String(describing: error).localizedCaseInsensitiveContains("stale location update rejected")
    }
}
