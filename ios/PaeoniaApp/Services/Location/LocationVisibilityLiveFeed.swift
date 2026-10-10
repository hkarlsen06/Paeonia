import Foundation

/// Keeps the cached partner location state current while the app is open.
/// Convex pushes a new result when the partner turns sharing on or off, sends
/// a new location, or the relationship ends. Each result goes into the
/// visibility store, which tells the view models to re-read.
nonisolated struct LocationVisibilityLiveFeed: LiveFeed {
    let name = "location_visibility"

    private let visibilityStore: any LocationVisibilitySnapshotPersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let now: @Sendable () -> Date

    init(
        visibilityStore: any LocationVisibilitySnapshotPersisting,
        pendingOperationStore: any PendingSyncOperationPersisting,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.visibilityStore = visibilityStore
        self.pendingOperationStore = pendingOperationStore
        self.now = now
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard let coupleID = session.activeCoupleID else {
            return
        }

        let results = live.subscribe(
            "location:get_partner_location_visibility",
            args: ["p_couple_id": coupleID.uuidString.lowercased()],
            as: [PartnerLocationVisibility].self
        )
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(rows) = result,
                  let snapshot = rows.first?.snapshot(ownerUserID: session.userID, refreshedAt: now())
            else {
                continue
            }
            await save(snapshot, ownerUserID: session.userID)
        }
    }

    private func save(_ snapshot: LocationVisibilitySnapshot, ownerUserID: UUID) async {
        // The outbox tells us about a choice from before a relaunch. A choice
        // made while this read runs is covered by the store, which checks for
        // it in the same step as the write. If the outbox read fails, keep the
        // local choice, since showing sharing as on by mistake is the worse error.
        let pending = try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLocationSharingPreference
        )
        guard !Task.isCancelled else {
            return
        }
        try? await visibilityStore.saveRemote(
            snapshot,
            preservingLocalSharingChoiceIf: pending.map { !$0.isEmpty } ?? true
        )
    }
}
