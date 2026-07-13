import Foundation

struct RelationshipDatePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .setRelationshipStartedOn

    private let gateway: any SupabaseRelationshipStartedOnGateway
    private let accessSnapshotStore: any AccessSyncSnapshotPersisting

    init(
        gateway: any SupabaseRelationshipStartedOnGateway,
        accessSnapshotStore: any AccessSyncSnapshotPersisting
    ) {
        self.gateway = gateway
        self.accessSnapshotStore = accessSnapshotStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing relationship start date payload")
        }

        let payload = try JSONDecoder().decode(
            SetRelationshipStartedOnOperationPayload.self,
            from: requestData
        )
        let startedOn = try PairingStartDate(rawValue: payload.startedOn)
        let confirmedStartedOn = try await gateway.setStartedOn(
            startedOn,
            operation: operation.operation
        )

        try await accessSnapshotStore.replaceRelationshipStartedOn(
            ownerUserID: operation.ownerUserID,
            startedOn: confirmedStartedOn,
            refreshedAt: Date()
        )
        return .succeeded
    }
}
