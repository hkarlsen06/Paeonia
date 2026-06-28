import Foundation
import Observation

/// The content of a still-sending text or partner-choice answer, for its "saved,
/// sending" preview. Resolved from the queued operation so nothing the user wrote
/// disappears while it's on its way. Media answers preview from their staged bytes
/// instead (see `sendingMediaData`).
nonisolated enum DailySendingSimpleContent: Equatable, Sendable {
    case text(String)
    case partnerChoice(name: String)
}

@MainActor
@Observable
final class DailyChallengeViewModel {
    /// A still-sending answer, reconstructed from the queued operation so the "saved,
    /// sending" preview survives relaunch and clears once the send lands.
    private enum SendingAnswer: Equatable {
        case text(String)
        case partnerChoice(UUID)
        case media(DailyAnswerMediaDraft, stagedData: Data?)
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
    private let encoder = JSONEncoder()
    private var localChangeSyncHandler: (@MainActor () async -> Void)?
    private var currentUserID: UUID?
    private var answerDrafts: [UUID: DailyAnswerDraft] = [:]

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
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil
    ) {
        self.service = service ?? DailyChallengeServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsDailyChallengeDraftStore.shared
        self.mediaDraftStore = mediaDraftStore ?? FileDailyAnswerMediaDraftStore.live()
        self.pendingOperationStore = pendingOperationStore ?? Self.makeDefaultPendingOperationStore()
    }

    private static func makeDefaultPendingOperationStore() -> any PendingSyncOperationPersisting {
        if let localStore = try? PaeoniaLocalStore() {
            return SwiftDataPendingSyncOperationRepository(container: localStore.container)
        }
        return InMemoryPendingSyncOperationRepository()
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

        self.currentUserID = newUserID
        // Restore any drafts this person saved earlier so reopening — or relaunching
        // the app — keeps their half-written answers.
        answerDrafts = newUserID.map { draftStore.drafts(for: $0) } ?? [:]
        snapshot = .empty(currentUserID: newUserID)

        guard newUserID != nil else { return }
        await reload()
    }

    func reload() async {
        guard let currentUserID else { return }

        isLoading = true
        do {
            snapshot = try await service.loadToday(currentUserID: currentUserID)
        } catch is CancellationError {
        } catch {
            notice = .loadFailed
        }
        await refreshStreak()
        await refreshSendingState()
        isLoading = false
    }

    /// Refreshes the couple's streak from the server. Best-effort: on failure the
    /// last known value is kept so the celebration still shows something real
    /// (the completion screen predicts today's increment on top of it).
    func refreshStreak() async {
        do {
            streak = try await service.loadStreak()
        } catch is CancellationError {
        } catch {
            // Keep the last known streak; the completion screen falls back gracefully.
        }
    }

    func startToday() async {
        guard let currentUserID, !isStarting else { return }

        isStarting = true
        do {
            snapshot = try await service.startToday(
                currentUserID: currentUserID,
                operation: operationProvider.makeOperation()
            )
        } catch is CancellationError {
        } catch {
            notice = .startFailed
        }
        isStarting = false
    }

    /// Sends the user's answer for a question, resolving the kind from the draft.
    /// Every kind is saved on the device first and sent in the background, so a
    /// network blip never loses what the user wrote — text and partner choice queue
    /// the answer directly, a photo or voice note stages its bytes and queues too.
    func submitAnswer(for question: DailyChallengeQuestion) async {
        guard submittingQuestionID == nil else { return }

        switch composeKind(for: question) {
        case .photo, .voice:
            await submitMediaAnswer(for: question)
        default:
            await submitSimpleAnswer(for: question)
        }
    }

    /// Saves a text or partner-choice answer on the device and queues it for sending,
    /// then nudges the sync engine to send it now if we're online (it retries in the
    /// background otherwise). This is local-first: a transient failure never surfaces
    /// an error or asks the user to retry — the queued answer is sent when it can be.
    private func submitSimpleAnswer(for question: DailyChallengeQuestion) async {
        guard let payload = makePayload(for: question), let currentUserID else {
            notice = .emptyAnswer
            return
        }

        let content: DailySubmitAnswerOperationPayload.Content
        let sending: SendingAnswer
        switch payload {
        case let .text(body):
            content = .text(body)
            sending = .text(body)
        case let .partnerChoice(userID):
            content = .partnerChoice(userID)
            sending = .partnerChoice(userID)
        case .media:
            // Media answers go through submitMediaAnswer and never reach here.
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        let operationPayload = DailySubmitAnswerOperationPayload(
            instanceID: question.id,
            answerID: UUID(),
            content: content
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
            notice = .submitFailed
            submittingQuestionID = nil
            return
        }

        // Saved and shown as sending right away; the queued operation now carries the
        // answer, so the editable draft can go.
        sendingAnswers[question.id] = sending
        clearDraft(for: question.id)
        submittingQuestionID = nil
        await localChangeSyncHandler?()
        await reload()
    }

    /// Stages a media answer (photo or voice) for background sending: the staged bytes
    /// stay on disk and a `.submitDailyAnswer` operation is queued, then the sync
    /// engine is nudged to upload and submit it (retrying if offline). The media is
    /// never lost — it's already on disk — and the question immediately reads as
    /// "saved, sending".
    private func submitMediaAnswer(for question: DailyChallengeQuestion) async {
        guard
            let media = answerDrafts[question.id]?.media,
            let stagedData = mediaDraftStore.stagedMediaData(instanceID: question.id),
            let currentUserID
        else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        let submitOperation = operationProvider.makeOperation()
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: question.id,
            answerID: UUID(),
            content: .media(
                    DailySubmitAnswerOperationPayload.Media(
                        draft: media,
                        coupleID: question.coupleID,
                        reserveOperation: operationProvider.makeOperation(),
                        finalizeOperation: operationProvider.makeOperation(),
                        stagedData: stagedData
                    )
                )
            )

        do {
            try await pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: currentUserID,
                    operation: submitOperation,
                    operationKind: .submitDailyAnswer,
                    idempotencyScope: "daily-answer:\(question.id.uuidString.lowercased())",
                    requestData: try encoder.encode(payload)
                )
            )
        } catch {
            notice = .submitFailed
            submittingQuestionID = nil
            return
        }

        // Show it as sending right away; drop the editable draft (the staged bytes stay
        // for the upload), then ask the sync engine to send it now if we're online.
        sendingAnswers[question.id] = .media(media, stagedData: stagedData)
        clearDraft(for: question.id)
        submittingQuestionID = nil
        await localChangeSyncHandler?()
        await reload()
    }

    /// Resolves the draft into a directly-sendable payload (text or partner choice),
    /// or nil when there's nothing to send yet. Photo answers go through their own
    /// upload path, so they resolve to nil here.
    private func makePayload(for question: DailyChallengeQuestion) -> DailyAnswerPayload? {
        switch composeKind(for: question) {
        case .partnerChoice:
            guard let selection = partnerChoiceSelection(for: question.id) else { return nil }
            return .partnerChoice(selection)
        case .text:
            let answerText = draftText(for: question.id).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answerText.isEmpty else { return nil }
            return .text(answerText)
        default:
            return nil
        }
    }

    /// Whether the current draft is complete enough to send — drives the flow's
    /// primary button and keeps Skip out of reach once an answer is in progress.
    func hasDraftToSubmit(for question: DailyChallengeQuestion) -> Bool {
        switch composeKind(for: question) {
        case .photo, .voice:
            return answerDrafts[question.id]?.media != nil
        default:
            return makePayload(for: question) != nil
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
        } catch is CancellationError {
        } catch is DailyChallengeEditLockedError {
            notice = .editLocked
            await reload()
        } catch {
            notice = .editFailed
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
        } catch is CancellationError {
        } catch is DailyChallengeEditLockedError {
            notice = .editLocked
            await reload()
        } catch {
            notice = .editFailed
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

        shufflingSlotNumber = question.slotNumber
        do {
            snapshot = try await service.shuffleQuestion(
                currentUserID: currentUserID,
                slotNumber: question.slotNumber,
                operation: operationProvider.makeOperation()
            )
            clearDraft(for: question.id)
        } catch is CancellationError {
        } catch is DailyChallengeShuffleLimitError {
            notice = .shuffleLimitReached
        } catch {
            notice = .shuffleFailed
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
            notice = .submitFailed
            return
        }

        do {
            try mediaDraftStore.writeStagedMedia(compressed.data, instanceID: questionID)
        } catch {
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
        guard let data = try? Data(contentsOf: url) else {
            notice = .submitFailed
            return
        }

        do {
            try mediaDraftStore.writeStagedMedia(data, instanceID: questionID)
        } catch {
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

    /// The content of a still-sending text or partner-choice answer, for its preview.
    /// Nil for media answers (they preview from their staged bytes) and for answers
    /// that aren't sending.
    func sendingSimpleContent(for instanceID: UUID) -> DailySendingSimpleContent? {
        switch sendingAnswers[instanceID] {
        case let .text(body):
            return .text(body)
        case let .partnerChoice(userID):
            return .partnerChoice(name: participants.name(for: userID))
        case .media(_, stagedData: _), nil:
            return nil
        }
    }

    /// The staged media bytes for a still-sending media answer, for its "saved,
    /// sending" preview. Reads the staged file first, then queued fallback bytes.
    /// Nil for text/partner-choice answers.
    func sendingMediaData(for instanceID: UUID) -> Data? {
        guard case let .media(_, stagedData: stagedData) = sendingAnswers[instanceID] else { return nil }
        return mediaDraftStore.stagedMediaData(instanceID: instanceID) ?? stagedData
    }

    /// The recorded length of a still-sending voice note, so its playback scrubber
    /// shows a duration before the local file finishes loading. Nil for photos.
    func sendingVoiceDurationMs(for instanceID: UUID) -> Int? {
        guard case let .media(media, stagedData: _) = sendingAnswers[instanceID],
              media.purpose == .voice
        else { return nil }
        return media.durationMs
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
                switch payload.content {
                case let .text(body):
                    return (payload.instanceID, .text(body))
            case let .partnerChoice(userID):
                return (payload.instanceID, .partnerChoice(userID))
            case let .media(media):
                return (payload.instanceID, .media(media.draft, stagedData: media.stagedData))
            }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func dismissNotice() {
        notice = nil
    }

    var homeCardState: DailyChallengeCardState {
        if isLoading && !snapshot.hasAnyQuestions {
            return DailyChallengeCardState(
                kind: .loading,
                answeredCount: snapshot.progress.ownAnsweredCount,
                totalCount: snapshot.progress.requiredQuestionCount
            )
        }
        return snapshot.homeCardState
    }
}
