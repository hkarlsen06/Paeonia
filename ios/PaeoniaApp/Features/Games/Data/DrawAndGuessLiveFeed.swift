import Foundation

/// Keeps the Draw & Guess part of the Games cache current while the app is open.
/// One subscription to `drawAndGuess:get_draw_and_guess` carries the game, the
/// current round with its guesses, the drawer's word choices, and the partner's
/// presence. Each result goes into the cache, then the game re-reads. The
/// couple's settings for the Games tab come from `GamesOverviewLiveFeed`.
nonisolated struct DrawAndGuessLiveFeed: LiveFeed {
    let name = "draw_and_guess"

    /// Read by the Games tab, and while the partner plays this game by the Home card
    /// and the tab badge.
    var activation: LiveFeedActivation {
        .gameState(.drawAndGuess)
    }

    private let cache: any GamesCaching

    init(cache: any GamesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("drawAndGuess:get_draw_and_guess", as: RemoteDrawAndGuessState.self)
        for await result in results {
            guard !Task.isCancelled else {
                break
            }
            guard case let .value(state) = result else {
                await cache.clearPresence(ownerUserID: session.userID, overview: false)
                LocalStoreChanges.post(.games, ownerUserID: session.userID)
                continue
            }
            await cache.saveState(state, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                break
            }
            LocalStoreChanges.post(.games, ownerUserID: session.userID)
        }
        await cache.clearPresence(ownerUserID: session.userID, overview: false)
        LocalStoreChanges.post(.games, ownerUserID: session.userID)
    }
}
