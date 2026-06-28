import Foundation

actor SyncCoordinator: SyncCoordinating {
    private let streams: [any SyncStream]
    private let stateStore: any SyncStatePersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let minimumForegroundSyncInterval: TimeInterval
    private let syncTimeoutNanoseconds: UInt64
    private let failedRunRetryDelay: TimeInterval

    private var session: SyncSession?
    private var hasStarted = false
    private var isSyncing = false
    private var needsFollowUpSync = false
    private var scheduledTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
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
        )
        let needsDefaultStores = stateStore == nil
            || pendingOperationStore == nil
            || needsDefaultStreamStores
        let fallbackStores = needsDefaultStores ? SyncCoordinatorDefaults.makeStores() : nil
        if streams.isEmpty {
            guard let resolvedAccessSnapshotStore = accessSnapshotStore ?? fallbackStores?.accessSnapshotStore,
                  let resolvedRelationshipEventStore = relationshipEventStore ?? fallbackStores?.relationshipEventStore,
                  let resolvedLocationVisibilityStore = locationVisibilityStore ?? fallbackStores?.locationVisibilityStore,
                  let resolvedOwnLocationStore = ownLocationStore ?? fallbackStores?.ownLocationStore else {
                preconditionFailure("Default sync streams require persistent sync stores")
            }

            self.streams = SyncCoordinatorDefaults.makeStreams(
                accessSnapshotStore: resolvedAccessSnapshotStore,
                relationshipEventStore: resolvedRelationshipEventStore,
                locationVisibilityStore: resolvedLocationVisibilityStore,
                ownLocationStore: resolvedOwnLocationStore,
                pendingOperationHandlers: pendingOperationHandlers
            )
        } else {
            self.streams = streams
        }

        guard let resolvedStateStore = stateStore ?? fallbackStores?.stateStore,
            let resolvedPendingOperationStore = pendingOperationStore ?? fallbackStores?.pendingOperationStore else {
            preconditionFailure("SyncCoordinator requires sync state and pending operation stores")
        }

        self.stateStore = resolvedStateStore
        self.pendingOperationStore = resolvedPendingOperationStore
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
            isSyncing = false
            needsFollowUpSync = false
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
        hasStarted = false
        isSyncing = false
        needsFollowUpSync = false
    }

    func resetForUserChange() {
        let oldUserID = session?.userID
        stop()
        session = nil
        lastForegroundSyncAt = nil

        if let oldUserID {
            Task {
                try? await pendingOperationStore.resetInFlight(ownerUserID: oldUserID)
            }
        }
    }

    func runOnce(reason: SyncRequestReason) async -> SyncRunResult {
        guard !isSyncing else {
            needsFollowUpSync = true
            return .coalesced()
        }

        guard session != nil else {
            return .skippedNoSession()
        }

        hasStarted = true
        isSyncing = true

        let result = await drainSyncRuns(startingReason: reason)
        isSyncing = false

        if result.status != .cancelled {
            await scheduleRetryIfNeeded(after: result)
        }

        return result
    }

    private func scheduleSync(reason: SyncRequestReason) {
        guard !isSyncing else {
            needsFollowUpSync = true
            return
        }

        guard session != nil else {
            return
        }

        isSyncing = true
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

            needsFollowUpSync = false

            if shouldSkipForInterval(reason: nextReason, now: Date()) {
                return lastResult ?? .skippedInterval()
            }

            let result = await performRunWithTimeout(reason: nextReason, session: session)
            lastResult = result

            if Task.isCancelled {
                return result
            }

            if needsFollowUpSync {
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
        let stream = AsyncStream<SyncRunResult> { continuation in
            let runTask = Task {
                let result = await performRun(reason: reason, session: session)
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
