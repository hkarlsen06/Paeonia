import Foundation

/// Keeps the Mind Meld cache current while the app is open. One subscription to
/// `mindMeld:get_mind_meld` carries the game with its rounds and the couple's
/// numbers. Each result goes into the cache, then the game re-reads.
nonisolated struct MindMeldLiveFeed: LiveFeed {
    let name = "mind_meld"

    private let cache: any MindMeldCaching

    init(cache: any MindMeldCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("mindMeld:get_mind_meld", as: RemoteMindMeldState.self)
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
