import Foundation

/// Keeps the partner's hearts current while the app is open. One subscription to
/// `hearts:get_hearts` carries how many hearts the partner has sent and how many
/// this person was shown. Each result goes into the cache, then Home re-reads.
nonisolated struct HeartsLiveFeed: LiveFeed {
    let name = "hearts"

    private let cache: any HeartsCaching

    init(cache: any HeartsCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("hearts:get_hearts", as: RemoteHeartsState.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(state) = result else {
                continue
            }
            await cache.save(state, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.hearts, ownerUserID: session.userID)
        }
    }
}
