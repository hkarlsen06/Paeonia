import Foundation

extension DailyChallengeViewModel {
    /// Best-effort wait for the snapshot that contains an unlocked partner reply after
    /// a just-sent answer. The queued operation can disappear a beat before that
    /// snapshot arrives, so sending state alone is not reveal readiness: returning in
    /// that gap makes an answering cover close before it can turn over to the exchange.
    ///
    /// The reply arrives as the next applied snapshot, from the live feed or from the
    /// reload after the send. The wait stays capped, so an offline answer never holds
    /// the flow open indefinitely; the queued send still retries in the background.
    @discardableResult
    func awaitAnswerReveal(for instanceID: UUID) async -> Bool {
        if hasRevealedPartnerAnswer(for: instanceID) { return true }

        let waiterID = UUID()
        let (applied, appliedContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        snapshotWaiters[waiterID] = appliedContinuation
        let timeout = Task {
            try? await Task.sleep(for: .seconds(1.2))
            appliedContinuation.finish()
        }
        defer {
            timeout.cancel()
            snapshotWaiters[waiterID] = nil
            appliedContinuation.finish()
        }

        return await withTaskCancellationHandler {
            for await _ in applied where hasRevealedPartnerAnswer(for: instanceID) {
                return true
            }
            return hasRevealedPartnerAnswer(for: instanceID)
        } onCancel: {
            appliedContinuation.finish()
        }
    }

    private func hasRevealedPartnerAnswer(for instanceID: UUID) -> Bool {
        knownQuestion(instanceID)?.canViewPartnerAnswer == true
    }

    /// Re-reads the local store when the live feeds write to it, so a partner's
    /// answer, shuffle, or new day and a new message preview appear without a reload.
    /// Outbox changes refresh the "saved, sending" state: an answer that finished
    /// sending, or one the server refused for good and put back in the drafts.
    /// The task ends when the signed-in user changes.
    func observeLiveUpdates(for userID: UUID) {
        liveUpdatesTask = Task { @MainActor [weak self] in
            for await change in LocalStoreChanges.changes(in: .dailyChallenge, .threadChat, .pendingOperations) {
                guard change.ownerUserID == userID else { continue }
                guard let self, self.currentUserID == userID else { return }
                switch change.domain {
                case .dailyChallenge:
                    await self.applyCachedSnapshot(for: userID)
                case .threadChat:
                    let summaries = await self.chatService.cachedThreadSummaries(ownerUserID: userID)
                    let readMarks = await self.chatService.chatReadMarks(ownerUserID: userID)
                    let seenAnswers = await self.chatService.seenPartnerAnswers(ownerUserID: userID)
                    guard self.currentUserID == userID else { return }
                    self.applyThreadSummaries(summaries)
                    self.chatReadMarks = readMarks
                    self.seenPartnerAnswerIDs = seenAnswers
                    self.uploadSeenPartnerAnswers()
                case .pendingOperations:
                    self.restoreReturnedDrafts(for: userID)
                    await self.refreshSendingState()
                default:
                    break
                }
            }
        }
    }

    private func applyCachedSnapshot(for userID: UUID) async {
        let snapshotCache = self.snapshotCache
        let cached = await Task.detached(priority: .userInitiated) {
            snapshotCache.load(ownerUserID: userID)
        }.value
        guard currentUserID == userID, let cached else { return }
        // The feed wrote this from a server result, so today's state is known.
        hasResolvedTodayState = true
        apply(cached.loadResult(currentUserID: userID, locale: .current))
        // A live result often follows a queued answer finishing its send, so the
        // "saved, sending" list is re-read here too, not only on full reloads.
        await refreshSendingState()
    }

    func applyThreadSummaries(_ summaries: [ThreadChatSummary]) {
        // Only question chats. A memory's comments and a story's replies have their own screens.
        threadSummariesByQuestionID = Dictionary(
            summaries.compactMap { summary in summary.questionID.map { ($0, summary) } },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Refreshes the couple's streak from the server. Best-effort: on failure the
    /// last known value is kept so the celebration still shows something real
    /// (the completion screen predicts today's increment on top of it).
    func refreshStreak() async {
        do {
            streak = try await service.loadStreak()
        } catch {
            // Keep the last known streak; the completion screen falls back gracefully.
            if !error.isCancellation {
                logFailure("Loading the couple streak failed", error)
            }
        }
    }

    /// Shows a just-restored streak at once, before the server refresh confirms it, so
    /// a failed refresh can't leave the restore offer up after the user paid.
    func applyRestoredStreak(_ count: Int) {
        streak.currentCount = max(streak.currentCount, count)
        streak.longestCount = max(streak.longestCount, count)
        streak.restoreAvailable = false
        streak.restorableCount = 0
        streak.restoreDeadline = nil
    }

    /// Sleeps until the active day ends, then drops it and reloads. Online, the live
    /// feed usually brings the new day first; offline this is what stops yesterday's
    /// questions from staying open to answers the server would never accept.
    func scheduleDayEnd() {
        dayEndTask?.cancel()
        dayEndTask = nil
        guard let endsAt = snapshot.currentDayEndsAt, let userID = currentUserID else { return }
        let now = self.now
        dayEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSince(now()))))
            guard !Task.isCancelled, let self, self.currentUserID == userID else { return }
            self.endCurrentDayIfNeeded()
            await self.reload()
        }
    }

    /// Drops the active day from the snapshot once it has ended.
    func endCurrentDayIfNeeded() {
        let ended = snapshot.endingCurrentDay(ifEndedBy: now())
        if ended != snapshot {
            snapshot = ended
        }
    }

    /// A refresh can fail after the screen already has a usable, previously-loaded
    /// challenge. Keep that state quietly; the debug log still captures the network
    /// failure, but the user should not see a banner for content that stayed usable.
    var shouldSurfaceLoadFailureNotice: Bool {
        !(hasResolvedTodayState && snapshot.hasAnyQuestions)
    }

    func cancelInFlightReload() {
        reloadTask?.cancel()
        reloadTask = nil
        reloadTaskUserID = nil
    }

    var hasCompletedRequiredDailyQuestions: Bool {
        let requiredCount = DailyChallengeProgress.requiredOwnQuestionCount
        guard snapshot.ownQuestions.count >= requiredCount else { return false }

        let completedCount = snapshot.ownQuestions.filter { question in
            question.hasOwnAnswer || sendingAnswers[question.id] != nil
        }.count
        return completedCount >= requiredCount
    }

    var homeCardState: DailyChallengeCardState {
        // Show loading until today's state first resolves for this user, so the empty
        // initial snapshot never flashes "no challenge" before the load settles.
        // Seeded current-day content shows immediately (it satisfies
        // `hasAnyCurrentDayQuestions`); once resolved the card keeps the real,
        // last-known state even while a refresh is in flight, so it never drops back
        // to loading.
        if !hasResolvedTodayState && !snapshot.hasAnyCurrentDayQuestions {
            return DailyChallengeCardState(
                kind: .loading,
                answeredCount: snapshot.progress.ownAnsweredCount,
                totalCount: snapshot.progress.requiredQuestionCount
            )
        }
        return snapshot.homeCardState
    }
}
