import Foundation

extension PaeoniaSyncService {
    /// Sign-out calls this before it leaves Clerk, while requests still carry
    /// the account's token, so writes that can still go out are not purged.
    /// Returns once the run finishes or `timeout` passes, whichever is first.
    /// A run still going then keeps sending until `resetForUserChange` stops it.
    func flushPendingWrites(timeout: Duration) async {
        guard session != nil else {
            return
        }

        let (done, signal) = AsyncStream<Void>.makeStream()
        Task {
            _ = await runOnce(reason: .localChange)
            signal.finish()
        }
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            signal.finish()
        }
        for await _ in done {}
        deadline.cancel()
    }

    func runOnce(reason: SyncRequestReason) async -> SyncRunResult {
        guard runLock == .free else {
            requestFollowUp(for: reason)
            await waitForActiveRunToFinish()
            return .coalesced()
        }

        guard let session else {
            return .skippedNoSession()
        }

        hasStarted = true
        followUpReason = nil
        runLock = .run
        let generation = sessionGeneration

        let result = await drainSyncRuns(
            startingReason: reason,
            session: session,
            sessionGeneration: generation
        )
        guard generation == sessionGeneration, self.session == session else {
            return result
        }
        releaseRunLock()

        if result.status != .cancelled {
            await scheduleRetryIfNeeded(after: result)
        }

        return result
    }

    /// The phone may have a connection again (`NetworkPathSnapshot.mayHaveReconnected`).
    /// Writes that failed only because it had none go now instead of after their retry
    /// delay. A run in progress takes it as a follow-up, so a burst of path changes makes
    /// at most one more run.
    func connectionCameBack() {
        guard hasStarted else {
            return
        }
        scheduleSync(reason: .reconnected)
    }

    /// Asks for another run after the one in progress, which may already have passed
    /// the waiting writes. Only a new write and a connection that came back need one.
    /// Another refresh needs none, since the run in progress reads every stream.
    private func requestFollowUp(for reason: SyncRequestReason) {
        switch reason {
        case .reconnected:
            // Its run also sends every write a `.localChange` run would.
            followUpReason = .reconnected
        case .localChange:
            followUpReason = followUpReason ?? .localChange
        case .startup, .foreground, .manualRefresh, .remoteNotification:
            break
        }
    }

    func scheduleSync(reason: SyncRequestReason) {
        guard runLock == .free else {
            requestFollowUp(for: reason)
            return
        }

        guard let session else {
            return
        }

        runLock = .run
        followUpReason = nil
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        let sessionGeneration = self.sessionGeneration
        scheduledTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
        scheduledTask = Task {
            await drainScheduledSync(
                reason: reason,
                session: session,
                sessionGeneration: sessionGeneration,
                scheduleGeneration: generation
            )
        }
    }

    private func drainScheduledSync(
        reason: SyncRequestReason,
        session: SyncSession,
        sessionGeneration: UInt64,
        scheduleGeneration: UInt64
    ) async {
        let result = await drainSyncRuns(
            startingReason: reason,
            session: session,
            sessionGeneration: sessionGeneration
        )
        finishScheduledSync(
            session: session,
            sessionGeneration: sessionGeneration,
            scheduleGeneration: scheduleGeneration
        )

        if result.status != .cancelled,
           !Task.isCancelled,
           sessionGeneration == self.sessionGeneration,
           session == self.session {
            await scheduleRetryIfNeeded(after: result)
        }
    }

    func drainSyncRuns(
        startingReason: SyncRequestReason,
        session: SyncSession,
        sessionGeneration: UInt64
    ) async -> SyncRunResult {
        var nextReason = startingReason
        var lastResult: SyncRunResult?

        while true {
            guard sessionGeneration == self.sessionGeneration,
                  session == self.session else {
                return lastResult ?? SyncRunResult.cancelled()
            }

            if shouldSkipForInterval(reason: nextReason, now: Date()) {
                return lastResult ?? .skippedInterval()
            }

            let result = await performRunWithTimeout(reason: nextReason, session: session)
            lastResult = result

            if Task.isCancelled {
                return result
            }

            guard let followUpReason else {
                return result
            }
            self.followUpReason = nil
            nextReason = followUpReason
        }
    }

    private func finishScheduledSync(
        session: SyncSession,
        sessionGeneration: UInt64,
        scheduleGeneration: UInt64
    ) {
        guard scheduleGeneration == self.scheduleGeneration,
              sessionGeneration == self.sessionGeneration,
              session == self.session else {
            return
        }

        scheduledTask = nil
        releaseRunLock()
    }

    func finishSessionTransition(
        session: SyncSession?,
        sessionGeneration: UInt64,
        scheduleGeneration: UInt64
    ) {
        guard sessionGeneration == self.sessionGeneration,
              scheduleGeneration == self.scheduleGeneration,
              session == self.session else {
            return
        }

        scheduledTask = nil
        releaseRunLock()

        if hasStarted, session != nil {
            scheduleSync(reason: .startup)
        }
    }

    /// Relationship cleanup runs before Root commits the replacement access
    /// route. Quiesce the current session here so an old-couple stream cannot
    /// repopulate SwiftData after the privacy purge has deleted its records.
    func quiesceActiveWorkForPrivacyPurge() async {
        if runLock == .privacyPurge {
            await waitForActiveRunToFinish()
        }

        let scheduledRun = scheduledTask
        let runningPipelines = Array(activePipelineTasks.values)
        scheduleGeneration &+= 1
        scheduledRun?.cancel()
        retryTask?.cancel()
        retryTask = nil
        runningPipelines.forEach { $0.cancel() }
        runLock = .privacyPurge
        followUpReason = nil

        for pipeline in runningPipelines {
            _ = await pipeline.value
        }
        if let scheduledRun {
            await scheduledRun.value
        }

        scheduledTask = nil
    }

    func finishPrivacyPurgeQuiescence() {
        runLock = .free
        resumeActiveRunWaiters()
    }

    /// Ends a run or a session handover. A privacy purge keeps the lock, and only
    /// `finishPrivacyPurgeQuiescence` gives it back.
    func releaseRunLock() {
        guard runLock == .run else {
            return
        }
        runLock = .free
        resumeActiveRunWaiters()
    }

    func waitForActiveRunToFinish() async {
        guard runLock != .free else {
            return
        }

        await withCheckedContinuation { continuation in
            activeRunWaiters.append(continuation)
        }
    }

    func resumeActiveRunWaiters() {
        let waiters = activeRunWaiters
        activeRunWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func scheduleRetryIfNeeded(after result: SyncRunResult) async {
        guard runLock == .free, hasStarted, let session else {
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
                try? await Task.sleep(for: .seconds(delay))
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
}
