import Foundation

struct LocationVisibilitySyncStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .location

    private let gateway: any SupabaseLocationGateway
    private let visibilityStore: any LocationVisibilitySnapshotPersisting

    init(
        gateway: any SupabaseLocationGateway,
        visibilityStore: any LocationVisibilitySnapshotPersisting
    ) {
        self.gateway = gateway
        self.visibilityStore = visibilityStore
    }

    nonisolated func scope(for session: SyncSession) -> SyncStreamScope? {
        guard let activeCoupleID = session.activeCoupleID else {
            return nil
        }
        return SyncStreamScope(kind: .couple, id: activeCoupleID)
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        guard let activeCoupleID = context.session.activeCoupleID else {
            return nil
        }

        guard let snapshot = try await gateway.loadPartnerLocationVisibility(
            ownerUserID: context.session.userID,
            coupleID: activeCoupleID
        ) else {
            return nil
        }

        try await visibilityStore.save(snapshot)
        return SyncCursor(updatedAt: snapshot.updatedAt, tieID: snapshot.coupleID)
    }

    func push(context _: SyncContext) async throws {}
}
