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
        guard !isSyncing else {
            if reason == .localChange {
                needsLocalChangeFollowUp = true
            }
            await waitForActiveRunToFinish()
            return .coalesced()
        }

        guard let session else {
            return .skippedNoSession()
        }

        hasStarted = true
        needsLocalChangeFollowUp = false
        isSyncing = true
        let generation = sessionGeneration

        let result = await drainSyncRuns(
            startingReason: reason,
            session: session,
            sessionGeneration: generation
        )
        guard generation == sessionGeneration, self.session == session else {
            return result
        }
        if !isPrivacyQuiescing {
            isSyncing = false
            resumeActiveRunWaiters()
        }

        if result.status != .cancelled {
            await scheduleRetryIfNeeded(after: result)
        }

        return result
    }

    func scheduleSync(reason: SyncRequestReason) {
        guard !isSyncing else {
            if reason == .localChange {
                needsLocalChangeFollowUp = true
            }
            return
        }

        guard let session else {
            return
        }

        isSyncing = true
        needsLocalChangeFollowUp = false
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

            let shouldRunFollowUpSync = needsLocalChangeFollowUp
            needsLocalChangeFollowUp = false

            if shouldRunFollowUpSync {
                nextReason = .localChange
            } else {
                return result
            }
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

        isSyncing = false
        scheduledTask = nil
        resumeActiveRunWaiters()
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
        isSyncing = false
        resumeActiveRunWaiters()

        if hasStarted, session != nil {
            scheduleSync(reason: .startup)
        }
    }

    /// Relationship cleanup runs before Root commits the replacement access
    /// route. Quiesce the current session here so an old-couple stream cannot
    /// repopulate SwiftData after the privacy purge has deleted its records.
    func quiesceActiveWorkForPrivacyPurge() async {
        if isPrivacyQuiescing {
            await waitForActiveRunToFinish()
        }

        let scheduledRun = scheduledTask
        let runningPipelines = Array(activePipelineTasks.values)
        scheduleGeneration &+= 1
        scheduledRun?.cancel()
        retryTask?.cancel()
        retryTask = nil
        runningPipelines.forEach { $0.cancel() }
        isPrivacyQuiescing = true
        isSyncing = true
        needsLocalChangeFollowUp = false

        for pipeline in runningPipelines {
            _ = await pipeline.value
        }
        if let scheduledRun {
            await scheduledRun.value
        }

        scheduledTask = nil
    }

    func finishPrivacyPurgeQuiescence() {
        isPrivacyQuiescing = false
        isSyncing = false
        resumeActiveRunWaiters()
    }

    func waitForActiveRunToFinish() async {
        guard isSyncing else {
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
}
