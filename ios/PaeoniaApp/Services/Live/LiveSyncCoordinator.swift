import Foundation

/// One live data source. A feed subscribes to backend queries and writes each
/// result into its repository or cache. View models never see a feed. They
/// observe the store through `LocalStoreChanges`.
nonisolated protocol LiveFeed: Sendable {
    /// Shown in logs and tests.
    var name: String { get }

    /// When the coordinator runs the feed. Defaults to `.always`.
    var activation: LiveFeedActivation { get }

    /// Runs until the task is cancelled. Return at once if the session has
    /// nothing to subscribe to (for example `activeCoupleID == nil`).
    /// The coordinator cancels the task and waits for it before it starts a new
    /// session or lets a privacy purge run, so a feed must stop writing after
    /// cancellation.
    func run(session: SyncSession, live: LiveQueryService) async
}

nonisolated extension LiveFeed {
    var activation: LiveFeedActivation {
        .always
    }
}

/// Start and stop live feeds with the sync session.
nonisolated protocol LiveSyncCoordinating: Actor {
    /// Runs every `.always` feed for `session`, and the other feeds whose topics
    /// are wanted (`LiveFeedDemand`). Does nothing when the same session is
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
    let feeds: [any LiveFeed]
    let live: LiveQueryService
    /// How long a `whileNeeded` feed keeps running after its last topic goes away.
    /// Switching back to a tab within this time costs no new subscription.
    let lingerDelay: Duration
    private(set) var runningSession: SyncSession?
    /// The `.always` feeds of the running session.
    private var tasks: [Task<Void, Never>] = []
    // Demand state for the `whileNeeded` feeds, keyed by index in `feeds`.
    // `LiveSyncCoordinator+Demand.swift` owns the logic.
    var heldTopics: Set<LiveFeedTopic> = []
    var heldSequence = 0
    /// Every topic touched so far. A restarted session touches them again, so a
    /// privacy purge does not leave a touched feed empty.
    var touchedTopics: Set<LiveFeedTopic> = []
    var scopedTasks: [Int: Task<Void, Never>] = [:]
    /// The last stopped run of each feed. A new run waits for it, so two runs
    /// of one feed never write at once.
    var retiredTasks: [Int: Task<Void, Never>] = [:]
    var lingerTimers: [Int: LingerTimer] = [:]
    var nextTimerToken = 0
    /// Finishes when every task cancelled so far has finished. Every caller of
    /// `cancelFeeds` awaits it, so none returns while an old feed can still write.
    private var draining: Task<Void, Never>?
    /// Bumped by `start`, `stop`, and `pause`. A `start` that suspended before a bump must not launch feeds.
    private var generation = 0
    private var pauseDepth = 0

    private var isPaused: Bool {
        pauseDepth > 0
    }

    init(feeds: [any LiveFeed], live: LiveQueryService, lingerDelay: Duration = .seconds(30)) {
        self.feeds = feeds
        self.live = live
        self.lingerDelay = lingerDelay
    }

    /// The coordinator the app uses: the feeds registered in `LiveFeedRegistry`
    /// on the shared ConvexMobile connection. It follows `LiveFeedDemand.shared`.
    @MainActor
    static func makeDefault() -> LiveSyncCoordinator? {
        guard PaeoniaLocalStore.shared != nil else {
            return nil
        }
        let coordinator = LiveSyncCoordinator(
            feeds: LiveFeedRegistry.makeFeeds(stores: PaeoniaSyncServiceDefaults.makeStores()),
            live: LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
        )
        LiveFeedDemand.shared.attach { event in await coordinator.apply(event) }
        return coordinator
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
        tasks = feeds.compactMap { feed in
            guard feed.activation.topics == nil else {
                return nil
            }
            return Task { await feed.run(session: session, live: live) }
        }
        reconcileScopedFeeds()
        touchScopedFeeds(touchedTopics)
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
        lingerTimers.values.forEach { $0.task.cancel() }
        lingerTimers = [:]
        let cancelled = tasks + Array(scopedTasks.values)
        tasks = []
        scopedTasks = [:]
        retiredTasks = [:]
        if !cancelled.isEmpty {
            retire(cancelled)
        }
        await draining?.value
    }

    /// Cancels `cancelled` and makes `draining` wait for them to finish.
    func retire(_ cancelled: [Task<Void, Never>]) {
        cancelled.forEach { $0.cancel() }
        let earlier = draining
        draining = Task {
            await earlier?.value
            for task in cancelled {
                await task.value
            }
        }
    }
}
