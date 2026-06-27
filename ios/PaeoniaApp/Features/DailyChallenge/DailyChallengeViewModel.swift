import Foundation
import Observation

@MainActor
@Observable
final class DailyChallengeViewModel {
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
    private(set) var sendingInstanceIDs: Set<UUID> = []
    private(set) var isLoading = false
    private(set) var isStarting = false
    private(set) var submittingQuestionID: UUID?
    private(set) var shufflingSlotNumber: Int?
    private(set) var notice: Notice?

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
        await refreshSendingState()
        isLoading = false
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
    /// Text and partner choice submit directly; a photo or voice note is staged and
    /// sent in the background.
    func submitAnswer(for question: DailyChallengeQuestion) async {
        guard submittingQuestionID == nil else { return }

        switch composeKind(for: question) {
        case .photo, .voice:
            await submitMediaAnswer(for: question)
        default:
            await submitSimpleAnswer(for: question)
        }
    }

    private func submitSimpleAnswer(for question: DailyChallengeQuestion) async {
        guard let payload = makePayload(for: question) else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        do {
            _ = try await service.submitAnswer(
                instanceID: question.id,
                answerID: UUID(),
                payload: payload,
                operation: operationProvider.makeOperation()
            )
            clearDraft(for: question.id)
            await reload()
        } catch is CancellationError {
        } catch {
            notice = .submitFailed
        }
        submittingQuestionID = nil
    }

    /// Stages a media answer (photo or voice) for background sending: the staged bytes
    /// stay on disk and a `.submitDailyAnswer` operation is queued, then the sync
    /// engine is nudged to upload and submit it (retrying if offline). The media is
    /// never lost — it's already on disk — and the question immediately reads as
    /// "saved, sending".
    private func submitMediaAnswer(for question: DailyChallengeQuestion) async {
        guard
            let media = answerDrafts[question.id]?.media,
            mediaDraftStore.stagedMediaData(instanceID: question.id) != nil,
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
            media: media,
            reserveOperation: operationProvider.makeOperation(),
            finalizeOperation: operationProvider.makeOperation()
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
        sendingInstanceIDs.insert(question.id)
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

    /// Whether a question's media answer is staged and waiting to finish sending in
    /// the background.
    func isSending(_ instanceID: UUID) -> Bool {
        sendingInstanceIDs.contains(instanceID)
    }

    /// The staged media bytes for a still-sending answer, for its "saved, sending"
    /// preview. Reads the staged file directly, since the editable draft is gone.
    func sendingMediaData(for instanceID: UUID) -> Data? {
        mediaDraftStore.stagedMediaData(instanceID: instanceID)
    }

    /// Recomputes which questions still have a queued/in-flight media answer, from the
    /// persisted operations — so the "sending" state survives relaunch and clears once
    /// the upload finishes.
    private func refreshSendingState() async {
        guard let currentUserID else {
            sendingInstanceIDs = []
            return
        }

        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: currentUserID,
            kind: .submitDailyAnswer
        )) ?? []

        sendingInstanceIDs = Set(
            operations.compactMap { operation -> UUID? in
                guard let data = operation.requestData,
                      let payload = try? JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
                else { return nil }
                return payload.instanceID
            }
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
