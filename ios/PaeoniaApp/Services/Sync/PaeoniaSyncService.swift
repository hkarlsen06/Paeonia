import Foundation

actor PaeoniaSyncService: PaeoniaSyncing {
    private let streams: [any SyncStream]
    private let stateStore: any SyncStatePersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let localPrivacyPurger: any LocalPrivacyPurging
    private let minimumForegroundSyncInterval: TimeInterval
    private let syncTimeoutNanoseconds: UInt64
    private let failedRunRetryDelay: TimeInterval

    private var session: SyncSession?
    private var hasStarted = false
    private var isSyncing = false
    // A follow-up pass is only needed when a *local write* was requested while a
    // run was already in flight: that run may have already drained the pending-
    // operations stream, so the new write needs another push. A foreground /
    // manual / startup refresh that coalesces onto an in-flight run needs no
    // second pass — the in-flight run already refreshes every read stream — so
    // it must not set this flag (that was the source of duplicate pipeline runs
    // on every scene activation).
    private var needsLocalChangeFollowUp = false
    private var activeRunWaiters: [CheckedContinuation<Void, Never>] = []
    private var scheduledTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var activePipelineTasks: [UUID: Task<SyncRunResult, Never>] = [:]
    private var scheduleGeneration: UInt64 = 0
    private var lastForegroundSyncAt: Date?

    init(
        streams: [any SyncStream] = [],
        stateStore: (any SyncStatePersisting)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        accessSnapshotStore: (any AccessSyncSnapshotPersisting)? = nil,
        relationshipEventStore: (any RelationshipSyncEventPersisting)? = nil,
        locationVisibilityStore: (any LocationVisibilitySnapshotPersisting)? = nil,
        ownLocationStore: (any OwnLocationSnapshotPersisting)? = nil,
        memoryStore: (any MemoryRecordPersisting)? = nil,
        privacyRecordStore: (any LocalPrivacyRecordPurging)? = nil,
        localPrivacyPurger: (any LocalPrivacyPurging)? = nil,
        pendingOperationHandlers: [any PendingSyncOperationHandling] = [],
        minimumForegroundSyncInterval: TimeInterval = 60,
        syncTimeoutNanoseconds: UInt64 = 30_000_000_000,
        failedRunRetryDelay: TimeInterval = 60
    ) {
        let needsDefaultStreamStores = streams.isEmpty
        && (
            accessSnapshotStore == nil
            || relationshipEventStore == nil
            || locationVisibilityStore == nil
            || ownLocationStore == nil
            || memoryStore == nil
        )
        let needsDefaultStores = stateStore == nil
            || pendingOperationStore == nil
            || needsDefaultStreamStores
            || (streams.isEmpty && privacyRecordStore == nil && localPrivacyPurger == nil)
        let fallbackStores = needsDefaultStores ? PaeoniaSyncServiceDefaults.makeStores() : nil
        let resolvedLocalPrivacyPurger: any LocalPrivacyPurging
        if let localPrivacyPurger {
            resolvedLocalPrivacyPurger = localPrivacyPurger
        } else if let resolvedPrivacyRecordStore = privacyRecordStore ?? fallbackStores?.privacyRecordStore {
            resolvedLocalPrivacyPurger = LocalPrivacyPurgeService(
                recordStore: resolvedPrivacyRecordStore
            )
        } else {
            resolvedLocalPrivacyPurger = NoOpLocalPrivacyPurger()
        }

        if streams.isEmpty {
            guard let resolvedAccessSnapshotStore = accessSnapshotStore ?? fallbackStores?.accessSnapshotStore,
                  let resolvedRelationshipEventStore = relationshipEventStore ?? fallbackStores?.relationshipEventStore,
                  let resolvedLocationVisibilityStore = locationVisibilityStore
                    ?? fallbackStores?.locationVisibilityStore,
                  let resolvedOwnLocationStore = ownLocationStore ?? fallbackStores?.ownLocationStore,
                  let resolvedMemoryStore = memoryStore ?? fallbackStores?.memoryStore else {
                preconditionFailure("Default sync streams require persistent sync stores")
            }

            self.streams = PaeoniaSyncServiceDefaults.makeStreams(
                accessSnapshotStore: resolvedAccessSnapshotStore,
                relationshipEventStore: resolvedRelationshipEventStore,
                locationVisibilityStore: resolvedLocationVisibilityStore,
                ownLocationStore: resolvedOwnLocationStore,
                memoryStore: resolvedMemoryStore,
                localPrivacyPurger: resolvedLocalPrivacyPurger,
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
    }

    func configure(session: SyncSession?) {
        let previousUserID = self.session?.userID
        self.session = session

        if previousUserID != nil, previousUserID != session?.userID {
            scheduleGeneration &+= 1
            scheduledTask?.cancel()
            scheduledTask = nil
            retryTask?.cancel()
            retryTask = nil
            activePipelineTasks.values.forEach { $0.cancel() }
            isSyncing = false
            needsLocalChangeFollowUp = false
            resumeActiveRunWaiters()
            lastForegroundSyncAt = nil
        }

        if hasStarted, session != nil {
            scheduleSync(reason: .startup)
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

    func purgeRelationshipAccess(ownerUserID: UUID, permanently: Bool) async {
        await localPrivacyPurger.purge(
            ownerUserID: ownerUserID,
            scope: permanently
                ? .relationshipContentPurged(clearAccessSnapshot: true)
                : .relationshipAccessHidden
        )
    }

    func runOnce(reason: SyncRequestReason) async -> SyncRunResult {
        guard !isSyncing else {
            if reason == .localChange {
                needsLocalChangeFollowUp = true
            }
            await waitForActiveRunToFinish()
            return .coalesced()
        }

        guard session != nil else {
            return .skippedNoSession()
        }

        hasStarted = true
        needsLocalChangeFollowUp = false
        isSyncing = true

        let result = await drainSyncRuns(startingReason: reason)
        isSyncing = false
        resumeActiveRunWaiters()

        if result.status != .cancelled {
            await scheduleRetryIfNeeded(after: result)
        }

        return result
    }

    private func scheduleSync(reason: SyncRequestReason) {
        guard !isSyncing else {
            if reason == .localChange {
                needsLocalChangeFollowUp = true
            }
            return
        }

        guard session != nil else {
            return
        }

        isSyncing = true
        needsLocalChangeFollowUp = false
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        scheduledTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
        scheduledTask = Task {
            await drainScheduledSync(reason: reason, generation: generation)
        }
    }

    private func drainScheduledSync(reason: SyncRequestReason, generation: UInt64) async {
        let result = await drainSyncRuns(startingReason: reason)
        finishScheduledSync(generation: generation)

        if result.status != .cancelled, !Task.isCancelled {
            await scheduleRetryIfNeeded(after: result)
        }
    }

    private func drainSyncRuns(startingReason: SyncRequestReason) async -> SyncRunResult {
        var nextReason = startingReason
        var lastResult: SyncRunResult?

        while true {
            guard let session else {
                return lastResult ?? .skippedNoSession()
            }

            if shouldSkipForInterval(reason: nextReason, now: Date()) {
                return lastResult ?? .skippedInterval()
            }

            let result = await performRunWithTimeout(reason: nextReason, session: session)
            lastResult = result

            if Task.isCancelled {
                return result
            }

            let shouldRunFollowUpSync = needsLocalChangeFollowUp
            needsLocalChangeFollowUp = false

            if shouldRunFollowUpSync {
                nextReason = .localChange
            } else {
                return result
            }
        }
    }

    private func finishScheduledSync(generation: UInt64) {
        guard generation == scheduleGeneration else {
            return
        }

        isSyncing = false
        scheduledTask = nil
        resumeActiveRunWaiters()
    }

    private func waitForActiveRunToFinish() async {
        guard isSyncing else {
            return
        }

        await withCheckedContinuation { continuation in
            activeRunWaiters.append(continuation)
        }
    }

    private func resumeActiveRunWaiters() {
        let waiters = activeRunWaiters
        activeRunWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func scheduleRetryIfNeeded(after result: SyncRunResult) async {
        guard !isSyncing, hasStarted, let session else {
            return
        }

        let now = Date()
        var retryDates: [Date] = []
        if let nextRetryAt = try? await pendingOperationStore.nextPendingOperationDate(
            ownerUserID: session.userID,
            now: now
        ) {
            retryDates.append(nextRetryAt)
        }

        if result.status == .failed || result.status == .timedOut {
            retryDates.append(now.addingTimeInterval(failedRunRetryDelay))
        }

        guard let retryAt = retryDates.min() else {
            retryTask?.cancel()
            retryTask = nil
            return
        }

        scheduleRetry(at: retryAt, session: session, generation: scheduleGeneration)
    }

    private func scheduleRetry(at retryAt: Date, session: SyncSession, generation: UInt64) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            let delay = max(0, retryAt.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else {
                return
            }

            await self?.runPendingOperationRetry(session: session, generation: generation)
        }
    }

    private func runPendingOperationRetry(session: SyncSession, generation: UInt64) {
        guard generation == scheduleGeneration,
              hasStarted,
              self.session == session
        else {
            return
        }

        retryTask = nil
        scheduleSync(reason: .localChange)
    }

    private func shouldSkipForInterval(reason: SyncRequestReason, now: Date) -> Bool {
        guard reason == .foreground else {
            return false
        }

        if let lastForegroundSyncAt,
           now.timeIntervalSince(lastForegroundSyncAt) < minimumForegroundSyncInterval {
            return true
        }

        lastForegroundSyncAt = now
        return false
    }

    private func performRunWithTimeout(
        reason: SyncRequestReason,
        session: SyncSession
    ) async -> SyncRunResult {
        let timeoutNanoseconds = syncTimeoutNanoseconds
        let pipelineID = UUID()
        let runTask = Task {
            await performRun(reason: reason, session: session)
        }
        activePipelineTasks[pipelineID] = runTask
        Task { [weak self] in
            _ = await runTask.value
            await self?.removeActivePipeline(pipelineID)
        }

        let stream = AsyncStream<SyncRunResult> { continuation in
            let resultTask = Task {
                let result = await runTask.value
                continuation.yield(result)
                continuation.finish()
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                runTask.cancel()
                continuation.yield(.timedOut())
                continuation.finish()
            }

            continuation.onTermination = { _ in
                runTask.cancel()
                resultTask.cancel()
                timeoutTask.cancel()
            }
        }

        for await result in stream {
            return result
        }

        return SyncRunResult(
            status: .cancelled,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    private func removeActivePipeline(_ id: UUID) {
        activePipelineTasks[id] = nil
    }

    private func performRun(
        reason: SyncRequestReason,
        session: SyncSession
    ) async -> SyncRunResult {
        let startedAt = Date()
        var attemptedStreamCount = 0
        var completedStreamCount = 0

        try? await pendingOperationStore.resetInFlight(ownerUserID: session.userID)

        for stream in streams {
            if Task.isCancelled {
                return SyncRunResult(
                    status: .cancelled,
                    attemptedStreamCount: attemptedStreamCount,
                    completedStreamCount: completedStreamCount,
                    failedStreamKey: nil,
                    errorDescription: nil
                )
            }

            let streamKey = stream.streamKey

            guard let scope = stream.scope(for: session) else {
                continue
            }

            attemptedStreamCount += 1

            do {
                let cursor = try await stateStore.cursor(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey
                )
                let context = SyncContext(
                    session: session,
                    reason: reason,
                    startedAt: startedAt,
                    streamCursor: cursor,
                    stateStore: stateStore,
                    pendingOperationStore: pendingOperationStore
                )

                try await stateStore.markAttempted(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey,
                    at: startedAt
                )
                let nextCursor = try await stream.pull(context: context)
                try Task.checkCancellation()
                try await stream.push(context: context)
                try Task.checkCancellation()
                try await stateStore.markSucceeded(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey,
                    cursor: nextCursor,
                    at: Date()
                )
                completedStreamCount += 1
            } catch is CancellationError {
                return SyncRunResult(
                    status: .cancelled,
                    attemptedStreamCount: attemptedStreamCount,
                    completedStreamCount: completedStreamCount,
                    failedStreamKey: streamKey,
                    errorDescription: nil
                )
            } catch {
                let errorDescription = String(describing: error)
                try? await stateStore.markFailed(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey,
                    errorDescription: errorDescription,
                    at: Date()
                )

                return SyncRunResult(
                    status: .failed,
                    attemptedStreamCount: attemptedStreamCount,
                    completedStreamCount: completedStreamCount,
                    failedStreamKey: streamKey,
                    errorDescription: errorDescription
                )
            }
        }

        return SyncRunResult(
            status: .succeeded,
            attemptedStreamCount: attemptedStreamCount,
            completedStreamCount: completedStreamCount,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }
}
