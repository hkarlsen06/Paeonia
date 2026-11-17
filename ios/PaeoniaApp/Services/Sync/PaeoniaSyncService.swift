import Foundation

/// Who holds the sync service's single run slot. A run, a session handover and a
/// privacy purge each need every other run to wait.
nonisolated enum SyncRunLock: Equatable, Sendable {
    case free
    /// A sync run or a session handover.
    case run
    /// Held from `quiesceActiveWorkForPrivacyPurge` until
    /// `finishPrivacyPurgeQuiescence`. Stopping or changing the session in
    /// between keeps it, so no run can write rows the purge is deleting.
    case privacyPurge
}

actor PaeoniaSyncService: PaeoniaSyncing {
    let streams: [any SyncStream]
    let stateStore: any SyncStatePersisting
    let pendingOperationStore: any PendingSyncOperationPersisting
    private let localPrivacyPurger: any LocalPrivacyPurging
    let minimumForegroundSyncInterval: TimeInterval
    let syncTimeout: Duration
    let failedRunRetryDelay: TimeInterval
    private let liveSync: (any LiveSyncCoordinating)?
    private let networkPaths: @Sendable () -> AsyncStream<NetworkPathSnapshot>

    var session: SyncSession?
    var hasStarted = false
    var runLock = SyncRunLock.free
    /// The run to make once the one in progress ends (`requestFollowUp`).
    var followUpReason: SyncRequestReason?
    var activeRunWaiters: [CheckedContinuation<Void, Never>] = []
    var scheduledTask: Task<Void, Never>?
    var retryTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    var activePipelineTasks: [UUID: Task<SyncRunResult, Never>] = [:]
    var scheduleGeneration: UInt64 = 0
    var sessionGeneration: UInt64 = 0
    var lastForegroundSyncAt: Date?

    init(
        streams: [any SyncStream] = [],
        stateStore: (any SyncStatePersisting)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        accessSnapshotStore: (any AccessSyncSnapshotPersisting)? = nil,
        locationVisibilityStore: (any LocationVisibilitySnapshotPersisting)? = nil,
        ownLocationStore: (any OwnLocationSnapshotPersisting)? = nil,
        memoryStore: (any MemoryRecordPersisting)? = nil,
        privacyRecordStore: (any LocalPrivacyRecordPurging)? = nil,
        localPrivacyPurger: (any LocalPrivacyPurging)? = nil,
        pendingOperationHandlers: [any PendingSyncOperationHandling] = [],
        minimumForegroundSyncInterval: TimeInterval = 60,
        syncTimeout: Duration = .seconds(30),
        failedRunRetryDelay: TimeInterval = 60,
        liveSync: (any LiveSyncCoordinating)? = nil,
        networkPaths: @escaping @Sendable () -> AsyncStream<NetworkPathSnapshot> = NetworkPathSnapshot.updates
    ) {
        let needsDefaultStreamStores = streams.isEmpty
        && (
            accessSnapshotStore == nil
            || locationVisibilityStore == nil
            || ownLocationStore == nil
            || memoryStore == nil
        )
        let needsDefaultStores = stateStore == nil
            || pendingOperationStore == nil
            || needsDefaultStreamStores
            || (streams.isEmpty && privacyRecordStore == nil && localPrivacyPurger == nil)
        let fallbackStores = needsDefaultStores ? PaeoniaSyncServiceDefaults.makeStores() : nil
        let resolvedLocalPrivacyPurger = Self.resolveLocalPrivacyPurger(
            localPrivacyPurger,
            privacyRecordStore: privacyRecordStore ?? fallbackStores?.privacyRecordStore
        )

        if streams.isEmpty {
            self.streams = Self.makeDefaultStreams(
                accessSnapshotStore: accessSnapshotStore ?? fallbackStores?.accessSnapshotStore,
                locationVisibilityStore: locationVisibilityStore ?? fallbackStores?.locationVisibilityStore,
                ownLocationStore: ownLocationStore ?? fallbackStores?.ownLocationStore,
                memoryStore: memoryStore ?? fallbackStores?.memoryStore,
                pendingOperationHandlers: pendingOperationHandlers
            )
        } else {
            self.streams = streams
        }

        guard let resolvedStateStore = stateStore ?? fallbackStores?.stateStore,
            let resolvedPendingOperationStore = pendingOperationStore ?? fallbackStores?.pendingOperationStore else {
            preconditionFailure("PaeoniaSyncService requires sync state and pending operation stores")
        }

        self.stateStore = resolvedStateStore
        self.pendingOperationStore = resolvedPendingOperationStore
        self.localPrivacyPurger = resolvedLocalPrivacyPurger
        self.minimumForegroundSyncInterval = minimumForegroundSyncInterval
        self.syncTimeout = syncTimeout
        self.failedRunRetryDelay = failedRunRetryDelay
        self.liveSync = liveSync
        self.networkPaths = networkPaths
    }

    private static func resolveLocalPrivacyPurger(
        _ localPrivacyPurger: (any LocalPrivacyPurging)?,
        privacyRecordStore: (any LocalPrivacyRecordPurging)?
    ) -> any LocalPrivacyPurging {
        if let localPrivacyPurger {
            return localPrivacyPurger
        }
        if let privacyRecordStore {
            return LocalPrivacyPurgeService(recordStore: privacyRecordStore)
        }
        return NoOpLocalPrivacyPurger()
    }

    private static func makeDefaultStreams(
        accessSnapshotStore: (any AccessSyncSnapshotPersisting)?,
        locationVisibilityStore: (any LocationVisibilitySnapshotPersisting)?,
        ownLocationStore: (any OwnLocationSnapshotPersisting)?,
        memoryStore: (any MemoryRecordPersisting)?,
        pendingOperationHandlers: [any PendingSyncOperationHandling]
    ) -> [any SyncStream] {
        guard let accessSnapshotStore, let locationVisibilityStore, let ownLocationStore, let memoryStore else {
            preconditionFailure("Default sync streams require persistent sync stores")
        }

        return PaeoniaSyncServiceDefaults.makeStreams(
            accessSnapshotStore: accessSnapshotStore,
            locationVisibilityStore: locationVisibilityStore,
            ownLocationStore: ownLocationStore,
            memoryStore: memoryStore,
            pendingOperationHandlers: pendingOperationHandlers
        )
    }

    func configure(session: SyncSession?) {
        guard self.session != session else {
            return
        }

        self.session = session
        sessionGeneration &+= 1
        scheduleGeneration &+= 1
        let transitionGeneration = sessionGeneration
        let transitionScheduleGeneration = scheduleGeneration
        let scheduledRun = scheduledTask
        let runningPipelines = Array(activePipelineTasks.values)

        scheduledRun?.cancel()
        retryTask?.cancel()
        retryTask = nil
        runningPipelines.forEach { $0.cancel() }
        followUpReason = nil
        lastForegroundSyncAt = nil

        guard scheduledRun != nil || !runningPipelines.isEmpty || runLock != .free else {
            scheduledTask = nil
            resumeActiveRunWaiters()
            if hasStarted, session != nil {
                scheduleSync(reason: .startup)
            }
            return
        }

        // Keep the sync lock held across the boundary. A replacement session
        // must not start until every task from the previous session has
        // settled, even when a stream is slow to cooperate with cancellation.
        if runLock == .free {
            runLock = .run
        }
        scheduledTask = Task {
            for pipeline in runningPipelines {
                _ = await pipeline.value
            }
            if let scheduledRun {
                await scheduledRun.value
            }

            finishSessionTransition(
                session: session,
                sessionGeneration: transitionGeneration,
                scheduleGeneration: transitionScheduleGeneration
            )
        }
    }

    func start() {
        // Before the guard, because `runOnce` also marks the service started.
        if connectionTask == nil {
            let paths = networkPaths()
            connectionTask = Task { [weak self] in
                var previous: NetworkPathSnapshot?
                for await path in paths {
                    if path.mayHaveReconnected(since: previous) {
                        await self?.connectionCameBack()
                    }
                    previous = path
                }
            }
        }
        guard !hasStarted else {
            return
        }

        hasStarted = true

        if session != nil {
            scheduleSync(reason: .startup)
        }
    }

    func stop() {
        scheduleGeneration &+= 1
        scheduledTask?.cancel()
        scheduledTask = nil
        retryTask?.cancel()
        retryTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        activePipelineTasks.values.forEach { $0.cancel() }
        hasStarted = false
        followUpReason = nil
        releaseRunLock()
    }

    func resetForUserChange() async {
        let oldUserID = session?.userID
        let scheduledRun = scheduledTask
        let runningPipelines = Array(activePipelineTasks.values)
        stop()
        for pipeline in runningPipelines {
            _ = await pipeline.value
        }
        if let scheduledRun {
            await scheduledRun.value
        }
        session = nil
        lastForegroundSyncAt = nil

        if let oldUserID {
            await localPrivacyPurger.purge(
                ownerUserID: oldUserID,
                scope: .departingUser
            )
        }
    }

    @discardableResult
    func purgeRelationshipAccess(
        ownerUserID: UUID,
        permanently: Bool
    ) async -> LocalPrivacyPurgeResult {
        // Live feeds write to the same store. Stop them before the purge deletes
        // rows, and accept new sessions again only after it finishes.
        await liveSync?.pause()
        await quiesceActiveWorkForPrivacyPurge()
        let result = await localPrivacyPurger.purge(
            ownerUserID: ownerUserID,
            scope: permanently
                ? .relationshipContentPurged(clearAccessSnapshot: true)
                : .relationshipAccessHidden
        )
        finishPrivacyPurgeQuiescence()
        await liveSync?.resume()
        return result
    }

    @discardableResult
    func retryPendingPrivacyPurges() async -> LocalPrivacyPurgeRetryResult {
        await localPrivacyPurger.retryPendingPurges()
    }

}
