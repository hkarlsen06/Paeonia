import Foundation

/// Keeps the topics overview current while the app is open, so the Topics card on
/// the Questions tab shows what the partner answered without a reload. Each result
/// goes into the cache, then the Topics view model re-reads.
nonisolated struct TopicsLiveFeed: LiveFeed {
    let name = "topics"

    /// Only the Topics card and shelf on the Questions tab read the overview.
    var activation: LiveFeedActivation {
        .whileNeeded([.questionsTab])
    }

    private let cache: any TopicsCaching

    init(cache: any TopicsCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        for await result in live.subscribe("topics:get_topics_overview", as: RemoteTopicsOverview.self) {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(overview) = result else {
                continue
            }
            await cache.saveOverview(overview, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.topics, ownerUserID: session.userID)
        }
    }
}
