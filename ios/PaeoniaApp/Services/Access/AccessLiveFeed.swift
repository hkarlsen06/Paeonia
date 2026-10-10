import Foundation

/// Keeps the cached access snapshot (entitlements and relationship state) equal
/// to the server. It runs for every signed-in user, paired or not. Root
/// observes the store change this feed causes and re-routes.
nonisolated struct AccessLiveFeed: LiveFeed {
    let name = "access"

    private let snapshotStore: any AccessSyncSnapshotPersisting

    init(snapshotStore: any AccessSyncSnapshotPersisting) {
        self.snapshotStore = snapshotStore
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        let results = live.subscribe("access:get_access_snapshot", as: [RemoteAccessSnapshot].self)
        for await result in results {
            if Task.isCancelled {
                return
            }
            guard case let .value(rows) = result else {
                continue
            }

            let remote = rows.first ?? RemoteAccessSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: nil
            )
            await save(remote, ownerUserID: session.userID)
        }
    }

    private func save(_ remote: RemoteAccessSnapshot, ownerUserID: UUID) async {
        // A resubscribe delivers the current value again. Skip it when nothing
        // changed so Root does not re-route (and purge) for an identical snapshot.
        if let stored = try? await snapshotStore.load(ownerUserID: ownerUserID),
           stored.userEntitlement == remote.userEntitlement,
           stored.coupleEntitlement == remote.coupleEntitlement,
           stored.relationshipState == remote.relationshipState {
            return
        }
        if Task.isCancelled {
            return
        }

        // A failed write leaves the old snapshot in place. The next server
        // change, or the next resubscribe, writes it again.
        try? await snapshotStore.save(
            AccessSyncSnapshot(
                ownerUserID: ownerUserID,
                userEntitlement: remote.userEntitlement,
                coupleEntitlement: remote.coupleEntitlement,
                relationshipState: remote.relationshipState,
                refreshedAt: Date()
            )
        )
    }
}
