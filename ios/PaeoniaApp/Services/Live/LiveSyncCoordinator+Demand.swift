import Foundation

/// A pending stop of a feed that lost its topics. The token tells a timer that a
/// later timer replaced it.
nonisolated struct LingerTimer {
    let token: Int
    let task: Task<Void, Never>
}

/// Starts and stops the `whileNeeded` feeds as the topics held by `LiveFeedDemand` change.
extension LiveSyncCoordinator {
    /// Applies one event from `LiveFeedDemand`.
    func apply(_ event: LiveFeedDemand.Event) {
        switch event {
        case let .held(topics, sequence):
            guard sequence > heldSequence else {
                return
            }
            heldSequence = sequence
            heldTopics = topics
            reconcileScopedFeeds()
        case let .touched(topics):
            touchedTopics.formUnion(topics)
            touchScopedFeeds(topics)
        }
    }

    /// Starts the feeds that serve a held topic and schedules the stop of the
    /// ones that no longer do. Does nothing without a running session.
    func reconcileScopedFeeds() {
        guard let session = runningSession else {
            return
        }
        for (index, feed) in feeds.enumerated() {
            guard let topics = feed.activation.topics else {
                continue
            }
            if !topics.isDisjoint(with: heldTopics) {
                lingerTimers.removeValue(forKey: index)?.task.cancel()
                startScopedFeed(at: index, session: session)
            } else if scopedTasks[index] != nil, lingerTimers[index] == nil {
                scheduleStop(ofFeedAt: index)
            }
        }
    }

    /// Starts the feeds that serve `touched` and lets them go after the linger
    /// time, unless a held topic keeps them.
    func touchScopedFeeds(_ touched: Set<LiveFeedTopic>) {
        guard let session = runningSession, !touched.isEmpty else {
            return
        }
        for (index, feed) in feeds.enumerated() {
            guard let topics = feed.activation.topics, !topics.isDisjoint(with: touched) else {
                continue
            }
            startScopedFeed(at: index, session: session)
            if topics.isDisjoint(with: heldTopics) {
                scheduleStop(ofFeedAt: index)
            }
        }
    }

    private func startScopedFeed(at index: Int, session: SyncSession) {
        guard scopedTasks[index] == nil else {
            return
        }
        let feed = feeds[index]
        let live = live
        let previous = retiredTasks[index]
        scopedTasks[index] = Task {
            await previous?.value
            guard !Task.isCancelled else {
                return
            }
            await feed.run(session: session, live: live)
        }
    }

    private func scheduleStop(ofFeedAt index: Int) {
        lingerTimers[index]?.task.cancel()
        nextTimerToken += 1
        let token = nextTimerToken
        let delay = lingerDelay
        lingerTimers[index] = LingerTimer(
            token: token,
            task: Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else {
                    return
                }
                await self?.stopScopedFeed(at: index, token: token)
            }
        )
    }

    private func stopScopedFeed(at index: Int, token: Int) {
        guard lingerTimers[index]?.token == token else {
            return
        }
        lingerTimers[index] = nil
        guard let topics = feeds[index].activation.topics,
              topics.isDisjoint(with: heldTopics),
              let task = scopedTasks.removeValue(forKey: index)
        else {
            return
        }
        retiredTasks[index] = task
        retire([task])
    }
}
