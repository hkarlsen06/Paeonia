import Foundation

/// One live data source. A feed subscribes to backend queries and writes each
/// result into its repository or cache. View models never see a feed. They
/// observe the store through `LocalStoreChanges`.
nonisolated protocol LiveFeed: Sendable {
    /// Shown in logs and tests.
    var name: String { get }

    /// Runs until the task is cancelled. Return at once if the session has
    /// nothing to subscribe to (for example `activeCoupleID == nil`).
    /// The coordinator cancels the task and waits for it before it starts a new
    /// session or lets a privacy purge run, so a feed must stop writing after
    /// cancellation.
    func run(session: SyncSession, live: LiveQueryService) async
}

/// Start and stop live feeds with the sync session.
nonisolated protocol LiveSyncCoordinating: Actor {
    /// Runs every feed for `session`. Does nothing when the same session is
    /// already running. Cancels the old feeds first when the session differs.
    /// Ignored while paused.
    func start(session: SyncSession) async
    /// Cancels every feed and waits until they finish. Used on sign-out.
    func stop() async
    /// Same as `stop`, and ignores `start` until a matching `resume`. Used around a
    /// privacy purge so a stale session cannot refill the store.
    func pause() async
    /// Accepts `start` calls again. It does not restart anything. The caller
    /// calls `start(session:)` with the session that is valid after the purge.
    func resume()
}

actor LiveSyncCoordinator: LiveSyncCoordinating {
    private let feeds: [any LiveFeed]
    private let live: LiveQueryService
    private var runningSession: SyncSession?
    private var tasks: [Task<Void, Never>] = []
    /// Finishes when every task cancelled so far has finished. Every caller of
    /// `cancelFeeds` awaits it, so none returns while an old feed can still write.
    private var draining: Task<Void, Never>?
    /// Bumped by `start`, `stop`, and `pause`. A `start` that suspended before a bump must not launch feeds.
    private var generation = 0
    private var pauseDepth = 0

    private var isPaused: Bool {
        pauseDepth > 0
    }

    init(feeds: [any LiveFeed], live: LiveQueryService) {
        self.feeds = feeds
        self.live = live
    }

    /// The coordinator the app uses: the feeds registered in `LiveFeedRegistry`
    /// on the shared ConvexMobile connection.
    @MainActor
    static func makeDefault() -> LiveSyncCoordinator? {
        guard PaeoniaLocalStore.shared != nil else {
            return nil
        }
        return LiveSyncCoordinator(
            feeds: LiveFeedRegistry.makeFeeds(stores: PaeoniaSyncServiceDefaults.makeStores()),
            live: LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
        )
    }

    var isRunning: Bool {
        runningSession != nil
    }

    func start(session: SyncSession) async {
        guard !isPaused, runningSession != session else {
            return
        }

        // Claim a generation so an older start that is still waiting for the
        // old feeds to finish gives way to this one.
        generation += 1
        let startGeneration = generation
        await cancelFeeds()
        // `cancelFeeds` suspends. A stop, a pause, or a newer start may have won.
        guard generation == startGeneration, !isPaused, runningSession == nil else {
            return
        }

        runningSession = session
        let live = live
        tasks = feeds.map { feed in
            Task { await feed.run(session: session, live: live) }
        }
    }

    func stop() async {
        generation += 1
        await cancelFeeds()
    }

    func pause() async {
        pauseDepth += 1
        generation += 1
        await cancelFeeds()
    }

    func resume() {
        pauseDepth = max(0, pauseDepth - 1)
    }

    private func cancelFeeds() async {
        runningSession = nil
        if !tasks.isEmpty {
            let cancelled = tasks
            tasks = []
            cancelled.forEach { $0.cancel() }
            let earlier = draining
            draining = Task {
                await earlier?.value
                for task in cancelled {
                    await task.value
                }
            }
        }
        await draining?.value
    }
}
