import Foundation

/// Keeps the Exquisite corpse cache current while the app is open. One
/// subscription to `exquisiteCorpse:get_exquisite_corpse` carries the game, the
/// figure in progress, the latest finished figures, and the idea deck for this
/// person's next part. Each result goes into the cache, then the game re-reads.
nonisolated struct ExquisiteCorpseLiveFeed: LiveFeed {
    let name = "exquisite_corpse"

    private let cache: any ExquisiteCorpseCaching

    init(cache: any ExquisiteCorpseCaching = FileExquisiteCorpseCache.shared) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("exquisiteCorpse:get_exquisite_corpse", as: RemoteExquisiteCorpseState.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(state) = result else {
                continue
            }
            await cache.saveState(state, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.games, ownerUserID: session.userID)
        }
    }
}
