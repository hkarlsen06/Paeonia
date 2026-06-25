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
        async let userEntitlement = gateway.loadMyEntitlement()
        async let coupleEntitlement = gateway.loadMyCoupleEntitlement()
        async let relationshipState = gateway.loadCurrentRelationshipState()

        try await snapshotStore.save(
            AccessSyncSnapshot(
                ownerUserID: context.session.userID,
                userEntitlement: userEntitlement,
                coupleEntitlement: coupleEntitlement,
                relationshipState: relationshipState,
                refreshedAt: Date()
            )
        )

        return nil
    }

    func push(context _: SyncContext) async throws {}
}
