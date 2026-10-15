import Foundation

actor PaeoniaSyncService: PaeoniaSyncing {
    let streams: [any SyncStream]
    let stateStore: any SyncStatePersisting
    let pendingOperationStore: any PendingSyncOperationPersisting
    private let localPrivacyPurger: any LocalPrivacyPurging
    let minimumForegroundSyncInterval: TimeInterval
    let syncTimeoutNanoseconds: UInt64
    let failedRunRetryDelay: TimeInterval
    private let liveSync: (any LiveSyncCoordinating)?

    var session: SyncSession?
    var hasStarted = false
    var isSyncing = false
    var isPrivacyQuiescing = false
    // A follow-up pass is only needed when a *local write* was requested while a
    // run was already in flight: that run may have already drained the pending-
    // operations stream, so the new write needs another push. A foreground /
    // manual / startup refresh that coalesces onto an in-flight run needs no
    // second pass — the in-flight run already refreshes every read stream — so
    // it must not set this flag (that was the source of duplicate pipeline runs
    // on every scene activation).
    var needsLocalChangeFollowUp = false
    var activeRunWaiters: [CheckedContinuation<Void, Never>] = []
    var scheduledTask: Task<Void, Never>?
    var retryTask: Task<Void, Never>?
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
        syncTimeoutNanoseconds: UInt64 = 30_000_000_000,
        failedRunRetryDelay: TimeInterval = 60,
        liveSync: (any LiveSyncCoordinating)? = nil
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
        self.syncTimeoutNanoseconds = syncTimeoutNanoseconds
        self.failedRunRetryDelay = failedRunRetryDelay
        self.liveSync = liveSync
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
        needsLocalChangeFollowUp = false
        lastForegroundSyncAt = nil

        guard scheduledRun != nil || !runningPipelines.isEmpty || isSyncing else {
            scheduledTask = nil
            isSyncing = false
            resumeActiveRunWaiters()
            if hasStarted, session != nil {
                scheduleSync(reason: .startup)
            }
            return
        }

        // Keep the sync lock held across the boundary. A replacement session
        // must not start until every task from the previous session has
        // settled, even when a stream is slow to cooperate with cancellation.
        isSyncing = true
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
        guard !hasStarted else {
            return
        }

        hasStarted = true

        if session != nil {
            scheduleSync(reason: .startup)
        }
    }

    func requestSync(reason: SyncRequestReason) {
        hasStarted = true

        guard session != nil else {
            return
        }

        scheduleSync(reason: reason)
    }

    func stop() {
        scheduleGeneration &+= 1
        scheduledTask?.cancel()
        scheduledTask = nil
        retryTask?.cancel()
        retryTask = nil
        activePipelineTasks.values.forEach { $0.cancel() }
        hasStarted = false
        isSyncing = false
        needsLocalChangeFollowUp = false
        resumeActiveRunWaiters()
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
