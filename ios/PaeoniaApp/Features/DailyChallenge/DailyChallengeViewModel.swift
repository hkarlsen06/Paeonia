import Foundation
import Observation
#if DEBUG
import OSLog
#endif

@MainActor
@Observable
final class DailyChallengeViewModel {
    /// A still-sending answer, reconstructed from the queued operation so the "saved,
    /// sending" preview survives relaunch and clears once the send lands. Any
    /// combination can be present (e.g. a photo with a caption).
    private struct SendingAnswer: Equatable {
        var text: String? = nil
        var partnerChoiceUserID: UUID? = nil
        var media: Media? = nil

        struct Media: Equatable {
            let draft: DailyAnswerMediaDraft
            let stagedData: Data?
        }
    }

    enum Notice: Equatable {
        case loadFailed
        case startFailed
        case submitFailed
        case emptyAnswer
        case shuffleLimitReached
        case shuffleFailed
        case editLocked
        case editFailed
    }

    private let service: any DailyChallengeServicing
    private let operationProvider: any SyncClientOperationProviding
    private let draftStore: any DailyChallengeDraftStoring
    private let mediaDraftStore: any DailyAnswerMediaDraftStoring
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let snapshotCache: any DailyChallengeSnapshotCaching
    private let encoder = JSONEncoder()
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "DailyChallenge"
    )
    #endif
    private var localChangeSyncHandler: (@MainActor () async -> Void)?
    private var currentUserID: UUID?
    private var reloadTask: Task<Void, Never>?
    private var reloadTaskUserID: UUID?
    private var answerDrafts: [UUID: DailyAnswerDraft] = [:]
    /// Whether today's challenge has resolved for the current user — set once the
    /// first load attempt has settled (applied a result or failed with a banner),
    /// not merely while a request is in flight. The home card shows its loading
    /// state until this is true, so the empty initial snapshot never flashes
    /// "no challenge" before we actually know; and once resolved the card keeps the
    /// real, last-known state through later refreshes instead of dropping back to
    /// loading. Reset when the signed-in user changes.
    private var hasResolvedTodayState = false

    private(set) var participants = DailyChallengeParticipants()
    private(set) var snapshot = DailyChallengeSnapshot.empty(currentUserID: nil)
    /// Questions whose answer is saved on the device and finishing its send in the
    /// background, keyed to what's being sent so the "saved, sending" preview can show
    /// the text, the picked person, or a photo/voice note (and a voice note's length)
    /// without the editable draft.
    private var sendingAnswers: [UUID: SendingAnswer] = [:]
    private(set) var isLoading = false
    private(set) var isStarting = false
    private(set) var submittingQuestionID: UUID?
    private(set) var shufflingSlotNumber: Int?
    private(set) var notice: Notice?
    /// The couple's shared streak, shown on the completion celebration. Loaded on
    /// demand and kept across failures so a transient error never blanks it.
    private(set) var streak = CoupleStreak.none

    init(
        service: (any DailyChallengeServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        draftStore: (any DailyChallengeDraftStoring)? = nil,
        mediaDraftStore: (any DailyAnswerMediaDraftStoring)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        snapshotCache: (any DailyChallengeSnapshotCaching)? = nil
    ) {
        self.service = service ?? DailyChallengeServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsDailyChallengeDraftStore.shared
        self.mediaDraftStore = mediaDraftStore ?? FileDailyAnswerMediaDraftStore.live()
        self.pendingOperationStore = pendingOperationStore ?? Self.makeDefaultPendingOperationStore()
        self.snapshotCache = snapshotCache ?? FileDailyChallengeSnapshotCache.live()
    }

    private static func makeDefaultPendingOperationStore() -> any PendingSyncOperationPersisting {
        if let localStore = try? PaeoniaLocalStore() {
            return SwiftDataPendingSyncOperationRepository(container: localStore.container)
        }
        return InMemoryPendingSyncOperationRepository()
    }

    /// Prints the real error behind a user-facing notice to the Xcode console in
    /// debug builds, so a failure that shows only a friendly banner can still be
    /// diagnosed. No-op in release.
    private func logFailure(_ context: String, _ error: Error) {
        #if DEBUG
        logger.error("\(context, privacy: .public): \(String(describing: error))")
        #endif
    }

    /// Whether an error just means the request was cancelled — a superseded or
    /// torn-down load (for example a fresh reload, or the screen going away), not a
    /// real failure. Foundation reports a cancelled URLSession task as
    /// `URLError.cancelled` (-999) rather than Swift's `CancellationError`, so both
    /// must be treated the same: swallowed silently, never shown as an error banner.
    private nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Wires the daily challenge to the app's sync engine so a just-queued media
    /// answer is flushed promptly (mirrors the location pattern).
    func setLocalChangeSyncHandler(_ handler: (@MainActor () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    /// Queued answers are already durable locally, so the answering flow should
    /// not wait for sync before moving on to the next question.
    private func syncQueuedAnswerInBackground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await localChangeSyncHandler?()
            await reload()
        }
    }

    /// Best-effort wait for a just-sent answer to finish sending and the snapshot to
    /// reload — the reload that unlocks a partner's reply once both have answered. A flow
    /// closing after a send can await this so the card it collapses into shows both
    /// answers at once instead of popping the partner's in a beat later.
    ///
    /// Polls the sending state rather than the network, so it returns the instant the
    /// send settles and is capped so a slow or offline connection never holds the UI
    /// open; the background send keeps running regardless. Cancellation-aware via the
    /// sleeps.
    func awaitAnswerReveal(for instanceID: UUID) async {
        guard isSending(instanceID) else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1.2))
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled || !isSending(instanceID) { return }
        }
    }

    /// Builds the view model for the Questions history flow, sharing this screen's
    /// service and current identity so the history reads through the same backend and
    /// labels answers with the same two people.
    func makeHistoryViewModel() -> DailyChallengeHistoryViewModel {
        DailyChallengeHistoryViewModel(
            service: service,
            currentUserID: currentUserID,
            participants: participants,
            // The partner's still-unanswered questions are carried-forward exchanges
            // that live in this snapshot, not the answered-history read model. Reading
            // them live keeps the history's actionable cards identical to the Questions
            // tab's, and answering one here updates both surfaces.
            pendingPartnerQuestions: { [weak self] in
                self?.snapshot.answerablePartnerQuestions ?? []
            }
        )
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
        isLoading = false
        // A new user hasn't resolved today's state yet, so the card returns to its
        // loading state until this user's first load settles.
        hasResolvedTodayState = false
        // Restore any drafts this person saved earlier so reopening — or relaunching
        // the app — keeps their half-written answers.
        answerDrafts = newUserID.map { draftStore.drafts(for: $0) } ?? [:]
        snapshot = .empty(currentUserID: newUserID)

        guard let newUserID else { return }

        // Seed from the local cache so the first render uses real data instead of
        // placeholders. The cache holds the last successful network load for this
        // specific user, so a different signed-in user never sees stale content.
        // `reload()` runs immediately after and replaces the seed with fresh data;
        // the seed is only visible during that first network round-trip.
        if let cached = snapshotCache.load(ownerUserID: newUserID) {
            // Guard: only apply if currentUserID hasn't changed underneath us.
            // Since `configure` is @MainActor and there is no suspension between
            // the assignment above and here, this check is always true — but it
            // documents the invariant explicitly.
            if self.currentUserID == newUserID {
                apply(cached.loadResult(currentUserID: newUserID, locale: .current))
            }
        }

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

        do {
            let result = try await service.loadToday(currentUserID: currentUserID)
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            apply(result)
        } catch {
            guard !Task.isCancelled, self.currentUserID == currentUserID else { return }
            if !isCancellation(error) {
                logFailure("Loading today's challenge failed", error)
                if shouldSurfaceLoadFailureNotice {
                    notice = .loadFailed
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
        } catch {
            if !isCancellation(error) {
                logFailure("Starting today's challenge failed", error)
                notice = .startFailed
            }
        }
        isStarting = false
    }

    /// Sends the user's answer for a question, resolving the kind(s) from the draft.
    /// Every kind is saved on the device first and sent in the background, so a
    /// network blip never loses what the user wrote. Questions that allow a photo or
    /// partner pick *alongside* text send whatever the user filled in, together.
    func submitAnswer(for question: DailyChallengeQuestion) async {
        guard submittingQuestionID == nil, let currentUserID else { return }

        guard let outgoing = resolveOutgoingAnswer(for: question) else {
            notice = .emptyAnswer
            return
        }

        await enqueueAnswer(outgoing, for: question, currentUserID: currentUserID)
    }

    private typealias OutgoingAnswer = (
        content: DailySubmitAnswerOperationPayload.Content,
        sending: SendingAnswer
    )

    /// Resolves the draft into the answer to queue and its "saved, sending" preview,
    /// or nil when there's nothing to send. Combined questions fold text together with
    /// a photo or partner pick; everything else stays single-kind.
    private func resolveOutgoingAnswer(for question: DailyChallengeQuestion) -> OutgoingAnswer? {
        let text = nonEmptyDraftText(for: question.id)

        if question.usesCombinedCompose {
            switch question.combinedSecondaryKind {
            case .photo:
                if let media = stagedMediaParts(for: question) {
                    if let text {
                        return (.textAndMedia(text, media.payload), SendingAnswer(text: text, media: media.sending))
                    }
                    return (.media(media.payload), SendingAnswer(media: media.sending))
                }
                return textOnly(text)
            case .partnerChoice:
                if let choice = partnerChoiceSelection(for: question.id) {
                    if let text {
                        return (.textAndPartnerChoice(text, choice), SendingAnswer(text: text, partnerChoiceUserID: choice))
                    }
                    return (.partnerChoice(choice), SendingAnswer(partnerChoiceUserID: choice))
                }
                return textOnly(text)
            default:
                return nil
            }
        }

        switch composeKind(for: question) {
        case .photo, .voice:
            guard let media = stagedMediaParts(for: question) else { return nil }
            return (.media(media.payload), SendingAnswer(media: media.sending))
        case .partnerChoice:
            guard let choice = partnerChoiceSelection(for: question.id) else { return nil }
            return (.partnerChoice(choice), SendingAnswer(partnerChoiceUserID: choice))
        case .text:
            return textOnly(text)
        default:
            return nil
        }
    }

    /// A text-only outgoing answer, or nil when there's no text.
    private func textOnly(_ text: String?) -> OutgoingAnswer? {
        guard let text else { return nil }
        return (.text(text), SendingAnswer(text: text))
    }

    /// Builds the queue and preview parts for a staged photo/voice draft, with fresh
    /// reserve/finalize operations fixed in the payload so retries stay idempotent.
    private func stagedMediaParts(
        for question: DailyChallengeQuestion
    ) -> (payload: DailySubmitAnswerOperationPayload.Media, sending: SendingAnswer.Media)? {
        guard
            let media = answerDrafts[question.id]?.media,
            let stagedData = mediaDraftStore.stagedMediaData(instanceID: question.id)
        else { return nil }

        let payload = DailySubmitAnswerOperationPayload.Media(
            draft: media,
            coupleID: question.coupleID,
            reserveOperation: operationProvider.makeOperation(),
            finalizeOperation: operationProvider.makeOperation(),
            stagedData: stagedData
        )
        return (payload, SendingAnswer.Media(draft: media, stagedData: stagedData))
    }

    /// Saves the resolved answer on the device and queues it for sending, then nudges
    /// the sync engine to send it now if we're online (it retries in the background
    /// otherwise). Local-first: a transient failure never surfaces an error — the
    /// queued answer is sent when it can be. Staged media bytes stay on disk for the
    /// upload; the handler clears them once it lands.
    private func enqueueAnswer(
        _ outgoing: OutgoingAnswer,
        for question: DailyChallengeQuestion,
        currentUserID: UUID
    ) async {
        submittingQuestionID = question.id
        let operationPayload = DailySubmitAnswerOperationPayload(
            instanceID: question.id,
            answerID: UUID(),
            content: outgoing.content
        )

        do {
            try await pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: currentUserID,
                    operation: operationProvider.makeOperation(),
                    operationKind: .submitDailyAnswer,
                    idempotencyScope: "daily-answer:\(question.id.uuidString.lowercased())",
                    requestData: try encoder.encode(operationPayload)
                )
            )
        } catch {
            logFailure("Saving an answer to send failed", error)
            notice = .submitFailed
            submittingQuestionID = nil
            return
        }

        // Shown as sending right away; the queued operation now carries the answer, so
        // the editable draft can go (staged media stays on disk for the upload).
        sendingAnswers[question.id] = outgoing.sending
        clearDraft(for: question.id)
        submittingQuestionID = nil
        syncQueuedAnswerInBackground()
    }

    /// The trimmed draft text for a question, or nil when it's empty.
    private func nonEmptyDraftText(for questionID: UUID) -> String? {
        let text = draftText(for: questionID).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Whether the current draft is complete enough to send — drives the flow's
    /// primary button and keeps Skip out of reach once an answer is in progress. A
    /// combined question needs only one of its parts filled in.
    func hasDraftToSubmit(for question: DailyChallengeQuestion) -> Bool {
        let hasText = nonEmptyDraftText(for: question.id) != nil
        let hasMedia = answerDrafts[question.id]?.media != nil
        let hasChoice = partnerChoiceSelection(for: question.id) != nil

        if question.usesCombinedCompose {
            switch question.combinedSecondaryKind {
            case .photo: return hasText || hasMedia
            case .partnerChoice: return hasText || hasChoice
            default: return hasText
            }
        }

        switch composeKind(for: question) {
        case .photo, .voice: return hasMedia
        case .partnerChoice: return hasChoice
        case .text: return hasText
        default: return false
        }
    }

    /// The kind the user is composing with for a question, honouring an explicit
    /// choice when the question accepts more than one kind, otherwise its default.
    func composeKind(for question: DailyChallengeQuestion) -> DailyChallengeAnswerKind? {
        if let selected = answerDrafts[question.id]?.selectedKind,
           question.composableAnswerKinds.contains(selected) {
            return selected
        }
        return question.defaultComposableKind
    }

    func setComposeKind(_ kind: DailyChallengeAnswerKind, for questionID: UUID) {
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.selectedKind = kind
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// Saves an edit to an answer the user already sent. Only allowed while the
    /// answer is still private; the backend rejects it once the partner has
    /// answered, which surfaces as a clear, non-retryable notice.
    func editTextAnswer(for question: DailyChallengeQuestion) async {
        guard question.editableAnswerKind == .text, submittingQuestionID == nil, shufflingSlotNumber == nil else { return }

        let answerText = draftText(for: question.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answerText.isEmpty else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        do {
            _ = try await service.editTextAnswer(
                instanceID: question.id,
                text: answerText,
                operation: operationProvider.makeOperation()
            )
            // Keep the draft equal to the saved text so the field reflects it and
            // Save disables again until the next change.
            setDraftText(answerText, for: question.id)
            await reload()
        } catch is DailyChallengeEditLockedError {
            notice = .editLocked
            await reload()
        } catch {
            if !isCancellation(error) {
                logFailure("Saving a text answer edit failed", error)
                notice = .editFailed
            }
        }
        submittingQuestionID = nil
    }

    /// Saves a changed partner-choice answer. Like the text edit, this is only
    /// allowed while the answer is still private; the backend locks it once the
    /// partner has answered, which surfaces as a clear, non-retryable notice.
    func editPartnerChoiceAnswer(for question: DailyChallengeQuestion) async {
        guard question.editableAnswerKind == .partnerChoice, submittingQuestionID == nil, shufflingSlotNumber == nil else { return }

        guard let selection = partnerChoiceSelection(for: question.id) else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        do {
            _ = try await service.editPartnerChoice(
                instanceID: question.id,
                selectedUserID: selection,
                operation: operationProvider.makeOperation()
            )
            // Keep the draft equal to the saved choice so Save disables again until
            // the next change.
            setPartnerChoice(selection, for: question.id)
            await reload()
        } catch is DailyChallengeEditLockedError {
            notice = .editLocked
            await reload()
        } catch {
            if !isCancellation(error) {
                logFailure("Saving a partner-choice answer edit failed", error)
                notice = .editFailed
            }
        }
        submittingQuestionID = nil
    }

    /// Swaps one of the user's own, still-unanswered questions for a fresh one.
    /// The backend caps the number of swaps per day; when that cap is hit we show
    /// a calm, plain-language notice instead of a generic error.
    func shuffle(_ question: DailyChallengeQuestion) async {
        guard
            question.origin == .own,
            !question.hasOwnAnswer,
            submittingQuestionID == nil,
            shufflingSlotNumber == nil,
            let currentUserID
        else { return }

        cancelInFlightReload()
        shufflingSlotNumber = question.slotNumber
        do {
            let result = try await service.shuffleQuestion(
                currentUserID: currentUserID,
                slotNumber: question.slotNumber,
                operation: operationProvider.makeOperation()
            )
            apply(result)
            clearDraft(for: question.id)
        } catch is DailyChallengeShuffleLimitError {
            notice = .shuffleLimitReached
        } catch {
            if !isCancellation(error) {
                logFailure("Skipping (shuffling) a question failed", error)
                notice = .shuffleFailed
            }
        }
        shufflingSlotNumber = nil
    }

    func isShuffling(_ question: DailyChallengeQuestion) -> Bool {
        shufflingSlotNumber == question.slotNumber
    }

    func draftText(for questionID: UUID) -> String {
        answerDrafts[questionID]?.text ?? ""
    }

    func setDraftText(_ text: String, for questionID: UUID) {
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.text = text
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    func partnerChoiceSelection(for questionID: UUID) -> UUID? {
        answerDrafts[questionID]?.partnerChoiceUserID
    }

    func setPartnerChoice(_ userID: UUID?, for questionID: UUID) {
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.partnerChoiceUserID = userID
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// The bytes of a staged-but-not-yet-sent photo or voice note, for the composer's
    /// preview.
    func stagedMediaData(for questionID: UUID) -> Data? {
        guard answerDrafts[questionID]?.media != nil else { return nil }
        return mediaDraftStore.stagedMediaData(instanceID: questionID)
    }

    /// The recorded length of a staged voice note, for the composer's preview.
    func stagedVoiceDurationMs(for questionID: UUID) -> Int? {
        answerDrafts[questionID]?.media?.durationMs
    }

    /// Compresses and stages a picked photo so it persists across reopen and is ready
    /// to upload. Selecting a photo also makes photo the chosen kind.
    func stagePhoto(_ imageData: Data, for questionID: UUID) {
        guard let compressed = ImageCompressor.compress(imageData) else {
            #if DEBUG
            logger.error("Compressing the picked photo returned nil; cannot stage it")
            #endif
            notice = .submitFailed
            return
        }

        do {
            try mediaDraftStore.writeStagedMedia(compressed.data, instanceID: questionID)
        } catch {
            logFailure("Staging a photo on the device failed", error)
            notice = .submitFailed
            return
        }

        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.selectedKind = .photo
        draft.media = DailyAnswerMediaDraft(
            purpose: .photo,
            mimeType: compressed.mediaType,
            fileExtension: compressed.fileExtension,
            width: compressed.width,
            height: compressed.height,
            durationMs: nil
        )
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// Stages a recorded voice note so it persists across reopen and is ready to
    /// upload. Reads the recording's bytes off the temporary file.
    func stageVoice(url: URL, durationMs: Int, for questionID: UUID) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logFailure("Reading the recorded voice note off disk failed", error)
            notice = .submitFailed
            return
        }

        do {
            try mediaDraftStore.writeStagedMedia(data, instanceID: questionID)
        } catch {
            logFailure("Staging a voice note on the device failed", error)
            notice = .submitFailed
            return
        }
        try? FileManager.default.removeItem(at: url)

        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.selectedKind = .voice
        draft.media = DailyAnswerMediaDraft(
            purpose: .voice,
            mimeType: "audio/mp4",
            fileExtension: "m4a",
            width: nil,
            height: nil,
            durationMs: durationMs
        )
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    /// Discards a staged photo or voice note (the bytes and the draft reference),
    /// keeping the chosen kind so the composer stays on that kind.
    func removeStagedMedia(for questionID: UUID) {
        mediaDraftStore.removeStagedMedia(instanceID: questionID)
        var draft = answerDrafts[questionID] ?? DailyAnswerDraft()
        draft.media = nil
        answerDrafts[questionID] = draft
        persist(draft, for: questionID)
    }

    private func persist(_ draft: DailyAnswerDraft, for questionID: UUID) {
        guard let currentUserID else { return }
        draftStore.setDraft(draft, for: questionID, userID: currentUserID)
    }

    private func clearDraft(for questionID: UUID) {
        answerDrafts[questionID] = nil
        if let currentUserID {
            draftStore.clearDraft(for: questionID, userID: currentUserID)
        }
    }

    /// Whether a question's answer is saved on the device and waiting to finish
    /// sending in the background.
    func isSending(_ instanceID: UUID) -> Bool {
        sendingAnswers[instanceID] != nil
    }

    /// The text of a still-sending answer (a standalone text answer or the caption on
    /// a combined photo/choice answer). Nil when there's no text or it isn't sending.
    func sendingText(for instanceID: UUID) -> String? {
        sendingAnswers[instanceID]?.text
    }

    /// The chosen person's name for a still-sending partner-choice answer. Nil
    /// otherwise.
    func sendingPartnerChoiceName(for instanceID: UUID) -> String? {
        guard let userID = sendingAnswers[instanceID]?.partnerChoiceUserID else { return nil }
        return participants.name(for: userID)
    }

    /// The staged media bytes for a still-sending media answer, for its "saved,
    /// sending" preview. Reads the staged file first, then queued fallback bytes.
    /// Nil for answers without media.
    func sendingMediaData(for instanceID: UUID) -> Data? {
        guard let media = sendingAnswers[instanceID]?.media else { return nil }
        return mediaDraftStore.stagedMediaData(instanceID: instanceID) ?? media.stagedData
    }

    /// The recorded length of a still-sending voice note, so its playback scrubber
    /// shows a duration before the local file finishes loading. Nil for photos.
    func sendingVoiceDurationMs(for instanceID: UUID) -> Int? {
        guard let media = sendingAnswers[instanceID]?.media, media.draft.purpose == .voice else { return nil }
        return media.draft.durationMs
    }

    /// Recomputes which questions still have a queued/in-flight answer, from the
    /// persisted operations — so the "sending" state survives relaunch and clears once
    /// the send finishes.
    private func refreshSendingState() async {
        guard let currentUserID else {
            sendingAnswers = [:]
            return
        }

        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: currentUserID,
            kind: .submitDailyAnswer
        )) ?? []

        sendingAnswers = Dictionary(
            operations.compactMap { operation -> (UUID, SendingAnswer)? in
                guard let data = operation.requestData,
                      let payload = try? JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
                else { return nil }
                return (payload.instanceID, Self.sendingAnswer(from: payload.content))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func sendingAnswer(
        from content: DailySubmitAnswerOperationPayload.Content
    ) -> SendingAnswer {
        switch content {
        case let .text(body):
            return SendingAnswer(text: body)
        case let .partnerChoice(userID):
            return SendingAnswer(partnerChoiceUserID: userID)
        case let .media(media):
            return SendingAnswer(media: .init(draft: media.draft, stagedData: media.stagedData))
        case let .textAndMedia(body, media):
            return SendingAnswer(text: body, media: .init(draft: media.draft, stagedData: media.stagedData))
        case let .textAndPartnerChoice(body, userID):
            return SendingAnswer(text: body, partnerChoiceUserID: userID)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func apply(_ result: DailyChallengeLoadResult) {
        snapshot = result.snapshot
        streak = result.streak
    }

    /// A refresh can fail after the screen already has a usable, previously-loaded
    /// challenge. Keep that state quietly; the debug log still captures the network
    /// failure, but the user should not see a banner for content that stayed usable.
    private var shouldSurfaceLoadFailureNotice: Bool {
        !(hasResolvedTodayState && snapshot.hasAnyQuestions)
    }

    private func cancelInFlightReload() {
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
