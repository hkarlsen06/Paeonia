import Foundation

/// Keeps the couple's reactions current while a screen that shows them is open. Each result of
/// `reactions:get_reactions` goes into the cache, then `ReactionStore` re-reads.
nonisolated struct ReactionsLiveFeed: LiveFeed {
    let name = "reactions"

    /// Stories and drawings show on Home, memories on the Memories tab, game creations on the
    /// Games tab, and the Us tab opens the game the partner is in.
    var activation: LiveFeedActivation {
        .whileNeeded([.homeTab, .memoriesTab, .gamesTab, .usTab])
    }

    private let cache: any ReactionsCaching

    init(cache: any ReactionsCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("reactions:get_reactions", as: RemoteReactions.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(remote) = result else {
                continue
            }
            await cache.save(remote.reactions, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.reactions, ownerUserID: session.userID)
        }
    }
}
