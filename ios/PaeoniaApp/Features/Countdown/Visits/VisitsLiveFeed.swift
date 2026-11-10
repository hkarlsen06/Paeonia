import Foundation

/// Keeps the couple's visits and list current while the Us tab shows them. Each result of
/// `visits:get_visits` goes into the cache, then the card and the visit screen re-read.
nonisolated struct VisitsLiveFeed: LiveFeed {
    /// The Us tab card, the visit screen and the dates timeline all open from the Us tab.
    var activation: LiveFeedActivation {
        .whileNeeded([.usTab])
    }

    private let cache: any VisitsCaching

    init(cache: any VisitsCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("visits:get_visits", as: RemoteCoupleVisits.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(remote) = result else {
                continue
            }
            await cache.save(remote.state, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for this task
            // before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.visits, ownerUserID: session.userID)
        }
    }
}
