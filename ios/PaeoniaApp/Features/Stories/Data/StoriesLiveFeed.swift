import Foundation

/// Keeps the couple's stories and notes current while the app is open. Each result of
/// `stories:get_stories` goes into the cache, then Home and the archive re-read.
nonisolated struct StoriesLiveFeed: LiveFeed {
    let name = "stories"

    private let cache: any StoriesCaching

    init(cache: any StoriesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("stories:get_stories", as: RemoteStories.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(remote) = result else {
                continue
            }
            await cache.save(remote.snapshot, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.stories, ownerUserID: session.userID)
        }
    }
}
