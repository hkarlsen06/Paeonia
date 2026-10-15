import Foundation
import Observation
#if DEBUG
import OSLog
#endif

@MainActor
@Observable
final class DailyChallengeViewModel {
    enum Notice: Equatable {
        case loadFailed(PaeoniaFailure)
        case startFailed(PaeoniaFailure)
        case submitFailed
        case emptyAnswer
        case shuffleLimitReached
        case shuffleFailed(PaeoniaFailure)
        case editLocked
        case editFailed
        case photoFailed
        case voiceFailed
        case dayEnded
    }

    let service: any DailyChallengeServicing
    let operationProvider: any SyncClientOperationProviding
    let draftStore: any DailyChallengeDraftStoring
    let mediaDraftStore: any DailyAnswerMediaDraftStoring
    let pendingOperationStore: any PendingSyncOperationPersisting
    private let snapshotCache: any DailyChallengeSnapshotCaching
    let chatService: any DailyQuestionChatServicing
    let now: @Sendable () -> Date
    let encoder = JSONEncoder()
    #if DEBUG
    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "DailyChallenge"
    )
    #endif
    private(set) var localChangeSyncHandler: (@MainActor () async -> Void)?
    private(set) var currentUserID: UUID?
    private var reloadTask: Task<Void, Never>?
    private var reloadTaskUserID: UUID?
    var answerDrafts: [UUID: DailyAnswerDraft] = [:]
    /// Whether today's challenge has resolved for the current user — set once the
    /// first load attempt has settled (applied a result or failed with a banner),
    /// not merely while a request is in flight. The home card shows its loading
    /// state until this is true, so the empty initial snapshot never flashes
    /// "no challenge" before we actually know; and once resolved the card keeps the
    /// real, last-known state through later refreshes instead of dropping back to
    /// loading. Reset when the signed-in user changes.
    var hasResolvedTodayState = false
    /// Callers of `awaitAnswerReveal`, signalled each time a snapshot is applied.
    private var snapshotWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var liveUpdatesTask: Task<Void, Never>?
    /// Wakes when the active couple day ends, so it stops showing as today even when
    /// no live update or reload arrives (for example offline at midnight).
    private var dayEndTask: Task<Void, Never>?
    /// One token per photo being prepared. A newer pick, a removal, or a skip replaces
    /// or clears it, so a slow earlier pick can't land on top of a later choice.
    var photoStagingTokens: [UUID: UUID] = [:]

    private(set) var participants = DailyChallengeParticipants()
    private(set) var snapshot = DailyChallengeSnapshot.empty(currentUserID: nil)
    /// Questions whose answer is saved on the device and finishing its send in the
    /// background, keyed to what's being sent so the "saved, sending" preview can show
    /// the text, the picked person, or a photo/voice note (and a voice note's length)
    /// without the editable draft.
    var sendingAnswers: [UUID: SendingAnswer] = [:]
    /// Bumped on every local send, so a store read that started before the send
    /// can't overwrite `sendingAnswers` with a list that misses it.
    var sendingGeneration = 0
    private(set) var isLoading = false
    private(set) var isStarting = false
    var submittingQuestionID: UUID?
    var shufflingSlotNumber: Int?
    var notice: Notice?
    /// The couple's shared streak, shown on the completion celebration. Loaded on
    /// demand and kept across failures so a transient error never blanks it.
    private(set) var streak = CoupleStreak.none
    private(set) var threadSummariesByQuestionID: [UUID: DailyQuestionThreadSummary] = [:]
    /// When the user last saw each chat on this phone, keyed by thread id.
    private(set) var chatReadMarks: [UUID: Date] = [:]
    /// Questions whose page the user has opened since the partner's answer showed up.
    private(set) var seenPartnerAnswerIDs: Set<UUID> = []
    /// Seen answers being sent to the server right now, so a second trigger doesn't
    /// send the same one twice.
    @ObservationIgnored var seenAnswerUploads: Set<UUID> = []
    /// The user sent an answer since the app started. The notification ask
    /// waits for this.
    @ObservationIgnored var hasSentAnswer = false
    /// The chat screen to open next, already read from this phone by `prepareChat(for:)`.
    @ObservationIgnored var preparedChat: DailyQuestionChatViewModel?

    init(
        service: (any DailyChallengeServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        draftStore: (any DailyChallengeDraftStoring)? = nil,
        mediaDraftStore: (any DailyAnswerMediaDraftStoring)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        snapshotCache: (any DailyChallengeSnapshotCaching)? = nil,
        chatService: (any DailyQuestionChatServicing)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.now = now
        self.service = service ?? DailyChallengeServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsDailyChallengeDraftStore.shared
        self.mediaDraftStore = mediaDraftStore ?? FileDailyAnswerMediaDraftStore.live()
        self.pendingOperationStore = pendingOperationStore ?? Self.makeDefaultPendingOperationStore()
        self.snapshotCache = snapshotCache ?? FileDailyChallengeSnapshotCache.live()
        if let chatService {
            self.chatService = chatService
        } else if service == nil {
            self.chatService = DailyQuestionChatServiceFactory.makeDefault()
        } else {
            self.chatService = EmptyDailyQuestionChatService()
        }
    }

    private static func makeDefaultPendingOperationStore() -> any PendingSyncOperationPersisting {
        if let localStore = PaeoniaLocalStore.shared {
            return SwiftDataPendingSyncOperationRepository(container: localStore.container)
        }
        return InMemoryPendingSyncOperationRepository()
    }

    /// Prints the real error behind a user-facing notice to the Xcode console in
    /// debug builds, so a failure that shows only a friendly banner can still be
    /// diagnosed. No-op in release.
    func logFailure(_ context: String, _ error: Error) {
        #if DEBUG
        logger.error("\(context, privacy: .public): \(String(describing: error))")
        #endif
    }

    /// Whether an error just means the request was cancelled — a superseded or
    /// torn-down load (for example a fresh reload, or the screen going away), not a
    /// real failure. Foundation reports a cancelled URLSession task as
    /// `URLError.cancelled` (-999) rather than Swift's `CancellationError`, so both
    /// must be treated the same: swallowed silently, never shown as an error banner.
    nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Wires the daily challenge to the app's sync engine so a just-queued media
    /// answer is flushed promptly (mirrors the location pattern).
    func setLocalChangeSyncHandler(_ handler: (@MainActor () async -> Void)?) {
        localChangeSyncHandler = handler
    }

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
        snapshot.questions.first(where: { $0.id == instanceID })?.canViewPartnerAnswer == true
    }

    func configure(currentUserID: UUID?) async {
        await configure(participants: DailyChallengeParticipants(currentUserID: currentUserID))
    }

    /// Configures the view model with both partners' identity. Display names may
    /// change without a reload; only a change of the signed-in user reloads and
    /// re-reads that person's drafts.
    func configure(participants: DailyChallengeParticipants) async {
        self.participants = participants
        let newUserID = participants.currentUserID

        guard self.currentUserID != newUserID else {
            if snapshot.currentUserID == nil, newUserID != nil {
                await reload()
            }
            return
        }

        self.currentUserID = newUserID
        reloadTask?.cancel()
        reloadTask = nil
        reloadTaskUserID = nil
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        dayEndTask?.cancel()
        dayEndTask = nil
        photoStagingTokens = [:]
        isLoading = false
        // A new user hasn't resolved today's state yet, so the card returns to its
        // loading state until this user's first load settles.
        hasResolvedTodayState = false
        // Restore any drafts this person saved earlier so reopening — or relaunching
        // the app — keeps their half-written answers.
        answerDrafts = newUserID.map { draftStore.drafts(for: $0) } ?? [:]
        snapshot = .empty(currentUserID: newUserID)
        sendingAnswers = [:]
        threadSummariesByQuestionID = [:]
        chatReadMarks = [:]
        seenPartnerAnswerIDs = []

        guard let newUserID else { return }

        observeLiveUpdates(for: newUserID)

        // Seed from the local cache so the first render uses real data instead of
        // placeholders. The cache holds the last successful network load for this
        // specific user, so a different signed-in user never sees stale content.
        // `reload()` runs immediately after and replaces the seed with fresh data;
        // the seed is only visible during that first network round-trip.
        let snapshotCache = self.snapshotCache
        let cached = await Task.detached(priority: .userInitiated) {
            snapshotCache.load(ownerUserID: newUserID)
        }.value
        // The disk read intentionally runs away from the main actor. Re-check the
        // identity after that suspension so a completed read for the previous user
        // can never update the newly signed-in user's screen.
        if self.currentUserID == newUserID, let cached {
            apply(cached.loadResult(currentUserID: newUserID, locale: .current))
        }
        let cachedThreads = await chatService.cachedThreadSummaries(ownerUserID: newUserID)
        let readMarks = await chatService.chatReadMarks(ownerUserID: newUserID)
        let seenAnswers = await chatService.seenPartnerAnswers(ownerUserID: newUserID)
        if self.currentUserID == newUserID {
            applyThreadSummaries(cachedThreads)
            chatReadMarks = readMarks
            seenPartnerAnswerIDs = seenAnswers
            uploadSeenPartnerAnswers()
        }
        // Answers still queued from before a relaunch count as answered from the first
        // frame, instead of showing an empty composer until the network load settles.
        await refreshSendingState()

        await reload()
    }

    /// Updates the partners' display data — names and profile photos — without
    /// touching the loaded question state. Cosmetic identity (a name or avatar that
    /// arrives or refreshes after launch) must not reload or, worse, cancel an
    /// in-flight load, so the view feeds those changes here while keying the load on
    /// the signed-in user alone. A change of the signed-in user still goes through
    /// `configure`, which reloads. See the `.task(id:)` note in AGENTS.md.
    func refreshParticipants(_ participants: DailyChallengeParticipants) {
        self.participants = participants
    }

    func reload() async {
        guard let currentUserID else { return }
        if let reloadTask, reloadTaskUserID == currentUserID {
            await reloadTask.value
            return
        }

        reloadTask?.cancel()
        let taskUserID = currentUserID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performReload(currentUserID: taskUserID)
        }
        reloadTask = task
        reloadTaskUserID = taskUserID

        await task.value
        if reloadTaskUserID == taskUserID {
            reloadTask = nil
            reloadTaskUserID = nil
        }
    }

    private func performReload(currentUserID: UUID) async {
        isLoading = true
        defer {
            if self.currentUserID == currentUserID {
                isLoading = false
            }
        }

        let threadSummariesTask = Task { [chatService] in
            try? await chatService.refreshThreadSummaries(ownerUserID: currentUserID)
        }

        do {
            let result = try await service.loadToday(currentUserID: currentUserID)
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            apply(result)
        } catch {
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            if !isCancellation(error) {
                logFailure("Loading today's challenge failed", error)
                if shouldSurfaceLoadFailureNotice {
                    notice = .loadFailed(PaeoniaFailure(error))
                }
            }
        }
        if let summaries = await threadSummariesTask.value,
           !Task.isCancelled, self.currentUserID == currentUserID {
            applyThreadSummaries(summaries)
        }
        guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
        // The first load for this user has now settled — either it applied a result
        // above or it failed (with the banner shown). Either way today's state is
        // resolved, so the home card stops showing loading and won't drop back to it
        // on later refreshes. A cancelled/superseded load returns before here and
        // lets the load that replaced it resolve instead.
        hasResolvedTodayState = true
        await refreshSendingState()
    }

    /// Re-reads the local store when the live feeds write to it, so a partner's
    /// answer, shuffle, or new day and a new message preview appear without a reload.
    /// Outbox changes refresh the "saved, sending" state: an answer that finished
    /// sending, or one the server refused for good and put back in the drafts.
    /// The task ends when the signed-in user changes.
    private func observeLiveUpdates(for userID: UUID) {
        liveUpdatesTask = Task { @MainActor [weak self] in
            for await change in LocalStoreChanges.changes(in: .dailyChallenge, .dailyChat, .pendingOperations) {
                guard change.ownerUserID == userID else { continue }
                guard let self, self.currentUserID == userID else { return }
                switch change.domain {
                case .dailyChallenge:
                    await self.applyCachedSnapshot(for: userID)
                case .dailyChat:
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

    func applyThreadSummaries(_ summaries: [DailyQuestionThreadSummary]) {
        threadSummariesByQuestionID = Dictionary(
            summaries.map { ($0.questionID, $0) },
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
            if !isCancellation(error) {
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

    func startToday() async {
        guard let currentUserID, !isStarting else { return }

        cancelInFlightReload()
        isStarting = true
        do {
            let result = try await service.startToday(
                currentUserID: currentUserID,
                operation: operationProvider.makeOperation()
            )
            apply(result)
            // This replaced any load it cancelled, so today's state is now known.
            hasResolvedTodayState = true
        } catch {
            if !isCancellation(error) {
                logFailure("Starting today's challenge failed", error)
                notice = .startFailed(PaeoniaFailure(error))
            }
        }
        isStarting = false
    }

    func dismissNotice() {
        notice = nil
    }

    func apply(_ result: DailyChallengeLoadResult) {
        // A cached day, or a response from just before the couple's day ended, must
        // not show as today.
        snapshot = result.snapshot.endingCurrentDay(ifEndedBy: now())
        streak = result.streak
        scheduleDayEnd()
        snapshotWaiters.values.forEach { $0.yield() }
        uploadSeenPartnerAnswers()
    }

    /// Drops the active day from the snapshot once it has ended.
    func endCurrentDayIfNeeded() {
        let ended = snapshot.endingCurrentDay(ifEndedBy: now())
        if ended != snapshot {
            snapshot = ended
        }
    }

    /// Sleeps until the active day ends, then drops it and reloads. Online, the live
    /// feed usually brings the new day first; offline this is what stops yesterday's
    /// questions from staying open to answers the server would never accept.
    private func scheduleDayEnd() {
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

    /// A refresh can fail after the screen already has a usable, previously-loaded
    /// challenge. Keep that state quietly; the debug log still captures the network
    /// failure, but the user should not see a banner for content that stayed usable.
    private var shouldSurfaceLoadFailureNotice: Bool {
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
