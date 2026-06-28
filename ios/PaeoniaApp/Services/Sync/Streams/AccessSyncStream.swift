import Foundation

struct AccessSyncStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .relationship

    private let gateway: any SupabaseAccessGateway
    private let snapshotStore: any AccessSyncSnapshotPersisting

    nonisolated init(
        gateway: any SupabaseAccessGateway,
        snapshotStore: any AccessSyncSnapshotPersisting
    ) {
        self.gateway = gateway
        self.snapshotStore = snapshotStore
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        let accessSnapshot = try await gateway.loadAccessSnapshot()

        try await snapshotStore.save(
            AccessSyncSnapshot(
                ownerUserID: context.session.userID,
                userEntitlement: accessSnapshot.userEntitlement,
                coupleEntitlement: accessSnapshot.coupleEntitlement,
                relationshipState: accessSnapshot.relationshipState,
                refreshedAt: Date()
            )
        )

        return nil
    }

    func push(context _: SyncContext) async throws {}
}
