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
    let firstDayDraftStore: any FirstDayAnswerDraftStoring
    let mediaDraftStore: any DailyAnswerMediaDraftStoring
    let pendingOperationStore: any PendingSyncOperationPersisting
    let snapshotCache: any DailyChallengeSnapshotCaching
    let chatService: any ThreadChatServicing
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
    var reloadTask: Task<Void, Never>?
    var reloadTaskUserID: UUID?
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
    var snapshotWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]
    var liveUpdatesTask: Task<Void, Never>?
    /// Wakes when the active couple day ends, so it stops showing as today even when
    /// no live update or reload arrives (for example offline at midnight).
    var dayEndTask: Task<Void, Never>?
    /// One token per photo being prepared. A newer pick, a removal, or a skip replaces
    /// or clears it, so a slow earlier pick can't land on top of a later choice.
    var photoStagingTokens: [UUID: UUID] = [:]
    /// Typed text waiting for its delayed save, by question. See `scheduleDraftSave`.
    @ObservationIgnored var pendingDraftSaves: [UUID: Task<Void, Never>] = [:]
    static let draftSaveDelay: Duration = .milliseconds(500)

    private(set) var participants = DailyChallengeParticipants()
    var snapshot = DailyChallengeSnapshot.empty(currentUserID: nil)
    /// The questions of the topics the user has opened, by question id (the topic
    /// instance id). Topics put them here (`setTopicQuestions`), so answering one uses
    /// the same drafts, send queue, reveal and chat as a daily question.
    private(set) var topicQuestions: [UUID: DailyChallengeQuestion] = [:]
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
    var streak = CoupleStreak.none
    var threadSummariesByQuestionID: [UUID: ThreadChatSummary] = [:]
    /// When the user last saw each chat on this phone, keyed by thread id.
    var chatReadMarks: [UUID: Date] = [:]
    /// Questions whose page the user has opened since the partner's answer showed up.
    var seenPartnerAnswerIDs: Set<UUID> = []
    /// Seen answers being sent to the server right now, so a second trigger doesn't
    /// send the same one twice.
    @ObservationIgnored var seenAnswerUploads: Set<UUID> = []
    /// The user sent an answer since the app started. The notification ask
    /// waits for this.
    @ObservationIgnored var hasSentAnswer = false
    /// An answer sent since the last `takeAnswerAwaitingPartner()` was to a daily
    /// question, not a topic one, that the partner had not answered yet.
    @ObservationIgnored var hasAnswerAwaitingPartner = false
    /// The chat screen to open next, already read from this phone by `prepareChat(for:)`.
    @ObservationIgnored var preparedChat: ThreadChatViewModel?

    init(
        service: (any DailyChallengeServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        draftStore: (any DailyChallengeDraftStoring)? = nil,
        firstDayDraftStore: (any FirstDayAnswerDraftStoring)? = nil,
        mediaDraftStore: (any DailyAnswerMediaDraftStoring)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        snapshotCache: (any DailyChallengeSnapshotCaching)? = nil,
        chatService: (any ThreadChatServicing)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.now = now
        self.service = service ?? DailyChallengeServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsDailyChallengeDraftStore.shared
        self.firstDayDraftStore = firstDayDraftStore ?? UserDefaultsFirstDayAnswerDraftStore.shared
        self.mediaDraftStore = mediaDraftStore ?? FileDailyAnswerMediaDraftStore.live()
        self.pendingOperationStore = pendingOperationStore ?? Self.makeDefaultPendingOperationStore()
        self.snapshotCache = snapshotCache ?? FileDailyChallengeSnapshotCache.live()
        if let chatService {
            self.chatService = chatService
        } else if service == nil {
            self.chatService = ThreadChatServiceFactory.makeDefault()
        } else {
            self.chatService = EmptyThreadChatService()
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

    /// Wires the daily challenge to the app's sync engine so a just-queued media
    /// answer is flushed promptly (mirrors the location pattern).
    func setLocalChangeSyncHandler(_ handler: (@MainActor () async -> Void)?) {
        localChangeSyncHandler = handler
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

        // Typed text still waiting for its save belongs to the previous user.
        flushDraftPersistence()
        resetState(forNewUser: newUserID)
        guard let newUserID else { return }

        observeLiveUpdates(for: newUserID)
        await seedFromLocalStore(for: newUserID)
        // Answers still queued from before a relaunch count as answered from the first
        // frame, instead of showing an empty composer until the network load settles.
        await refreshSendingState()

        await reload()
    }

    private func resetState(forNewUser newUserID: UUID?) {
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
        topicQuestions = [:]
        sendingAnswers = [:]
        threadSummariesByQuestionID = [:]
        chatReadMarks = [:]
        seenPartnerAnswerIDs = []
    }

    private func seedFromLocalStore(for newUserID: UUID) async {
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
            apply(cached.loadResult(currentUserID: newUserID, locale: .current), fromCache: true)
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

        do {
            let result = try await service.loadToday(currentUserID: currentUserID)
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            apply(result)
        } catch {
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            if !error.isCancellation {
                logFailure("Loading today's challenge failed", error)
                if shouldSurfaceLoadFailureNotice {
                    notice = .loadFailed(PaeoniaFailure(error))
                }
            }
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
            if !error.isCancellation {
                logFailure("Starting today's challenge failed", error)
                notice = .startFailed(PaeoniaFailure(error))
            }
        }
        isStarting = false
    }

    func dismissNotice() {
        notice = nil
    }

    /// Today's copy of a question, or the topic copy when it is a topic question.
    func knownQuestion(_ id: UUID) -> DailyChallengeQuestion? {
        snapshot.questions.first(where: { $0.id == id }) ?? topicQuestions[id]
    }

    /// Replaces one topic's questions. A topic's rows change when the partner answers
    /// or a send lands, so this also wakes an answer flow waiting for the reveal.
    func setTopicQuestions(_ questions: [DailyChallengeQuestion], topicKey: String) {
        var merged = topicQuestions.filter { $0.value.topicKey != topicKey }
        for question in questions {
            merged[question.id] = question
        }
        guard merged != topicQuestions else { return }
        topicQuestions = merged
        snapshotWaiters.values.forEach { $0.yield() }
        uploadSeenPartnerAnswers()
    }

    /// `fromCache` is true for the copy saved on this phone. Its questions may be
    /// from an earlier day, so first day text waits for the server's answer.
    func apply(_ result: DailyChallengeLoadResult, fromCache: Bool = false) {
        // A cached day, or a response from just before the couple's day ended, must
        // not show as today.
        snapshot = result.snapshot.endingCurrentDay(ifEndedBy: now())
        if !fromCache {
            adoptFirstDayDrafts()
        }
        streak = result.streak
        scheduleDayEnd()
        snapshotWaiters.values.forEach { $0.yield() }
        uploadSeenPartnerAnswers()
    }

}
