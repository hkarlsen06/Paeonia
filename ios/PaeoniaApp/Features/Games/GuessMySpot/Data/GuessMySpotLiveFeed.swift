import Foundation

/// Keeps the Guess my spot cache current while the app is open. One subscription
/// to `guessMySpot:get_guess_my_spot` carries the game and its two newest rounds.
/// Each result goes into the cache, then the game re-reads.
nonisolated struct GuessMySpotLiveFeed: LiveFeed {
    let name = "guess_my_spot"

    private let cache: any GuessMySpotCaching

    init(cache: any GuessMySpotCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("guessMySpot:get_guess_my_spot", as: RemoteGuessMySpotState.self)
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
