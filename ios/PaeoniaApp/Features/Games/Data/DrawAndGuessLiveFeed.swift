import Foundation

/// Keeps the Games cache current while the app is open. One subscription to
/// `games:get_draw_and_guess` carries the couple's settings, the game, the
/// current round with its guesses, the drawer's word choices, and the partner's
/// presence. Each result goes into the cache, then the hub and the game re-read.
nonisolated struct DrawAndGuessLiveFeed: LiveFeed {
    let name = "draw_and_guess"

    private let cache: any GamesCaching

    init(cache: any GamesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("games:get_draw_and_guess", as: RemoteDrawAndGuessState.self)
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
