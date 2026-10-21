import Foundation

/// Keeps the Story Chain cache current while the app is open. One subscription
/// to `storyChain:get_story_chain` carries the game, the current and previous
/// story, and the opening and word suggestions. Each result goes into the
/// cache, then the game re-reads. The couple's settings and the partner's
/// presence come from `GamesOverviewLiveFeed`.
nonisolated struct StoryChainLiveFeed: LiveFeed {
    let name = "story_chain"

    /// Read by the Games tab, and while the partner plays this game by the Home card
    /// and the tab badge.
    var activation: LiveFeedActivation {
        .gameState(.storyChain)
    }

    private let cache: any StoryChainCaching

    init(cache: any StoryChainCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("storyChain:get_story_chain", as: RemoteStoryChainState.self)
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
