import Foundation

/// Keeps the couple's countdowns and birthdays current while the app is open. Each
/// result of `countdowns:get_countdowns` goes into the cache, then the timeline re-reads.
nonisolated struct CoupleDatesLiveFeed: LiveFeed {
    let name = "coupleDates"

    private let cache: any CoupleDatesCaching

    init(cache: any CoupleDatesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("countdowns:get_countdowns", as: RemoteCoupleDates.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(remote) = result else {
                continue
            }
            await cache.save(remote.dates, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.coupleDates, ownerUserID: session.userID)
        }
    }
}
