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
    private let mediaUploadService: any DailyAnswerMediaUploading
    private let mediaDraftStore: any DailyAnswerMediaDraftStoring
    private var currentUserID: UUID?
    private var answerDrafts: [UUID: DailyAnswerDraft] = [:]

    private(set) var participants = DailyChallengeParticipants()
    private(set) var snapshot = DailyChallengeSnapshot.empty(currentUserID: nil)
    private(set) var isLoading = false
    private(set) var isStarting = false
    private(set) var submittingQuestionID: UUID?
    private(set) var shufflingSlotNumber: Int?
    private(set) var notice: Notice?

    init(
        service: (any DailyChallengeServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        draftStore: (any DailyChallengeDraftStoring)? = nil,
        mediaUploadService: (any DailyAnswerMediaUploading)? = nil,
        mediaDraftStore: (any DailyAnswerMediaDraftStoring)? = nil
    ) {
        self.service = service ?? DailyChallengeServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.draftStore = draftStore ?? UserDefaultsDailyChallengeDraftStore.shared
        self.mediaUploadService = mediaUploadService ?? DailyAnswerMediaUploadServiceFactory.makeDefault()
        self.mediaDraftStore = mediaDraftStore ?? FileDailyAnswerMediaDraftStore.live()
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
    /// Text and partner choice submit directly; a photo is uploaded first, then its
    /// asset id is submitted.
    func submitAnswer(for question: DailyChallengeQuestion) async {
        guard submittingQuestionID == nil else { return }

        if composeKind(for: question) == .photo {
            await submitPhotoAnswer(for: question)
        } else {
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

    /// Uploads the staged photo, then submits its media asset id. The photo's
    /// `answer_id` doubles as the media's reserved parent, so it's generated once and
    /// used for both the upload and the submit. On failure the staged photo is kept
    /// so the user can retry without re-picking.
    private func submitPhotoAnswer(for question: DailyChallengeQuestion) async {
        guard
            let media = answerDrafts[question.id]?.media,
            let bytes = mediaDraftStore.stagedMediaData(instanceID: question.id)
        else {
            notice = .emptyAnswer
            return
        }

        submittingQuestionID = question.id
        let answerID = UUID()
        let uploadable = DailyAnswerUploadMedia(
            data: bytes,
            purpose: media.purpose,
            mimeType: media.mimeType,
            fileExtension: media.fileExtension,
            width: media.width,
            height: media.height,
            durationMs: media.durationMs
        )

        do {
            let assetID = try await mediaUploadService.uploadMedia(
                uploadable,
                answerID: answerID,
                reserveOperation: operationProvider.makeOperation(),
                finalizeOperation: operationProvider.makeOperation()
            )
            _ = try await service.submitAnswer(
                instanceID: question.id,
                answerID: answerID,
                payload: .media([assetID]),
                operation: operationProvider.makeOperation()
            )
            clearMediaDraft(for: question.id)
            await reload()
        } catch is CancellationError {
        } catch {
            notice = .submitFailed
        }
        submittingQuestionID = nil
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
        if composeKind(for: question) == .photo {
            return answerDrafts[question.id]?.media != nil
        }
        return makePayload(for: question) != nil
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
        guard question.canEditOwnAnswer, submittingQuestionID == nil, shufflingSlotNumber == nil else { return }

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

    /// The bytes of a picked-but-not-yet-sent photo, for the composer's preview.
    func stagedPhotoData(for questionID: UUID) -> Data? {
        guard answerDrafts[questionID]?.media != nil else { return nil }
        return mediaDraftStore.stagedMediaData(instanceID: questionID)
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

    /// Discards a staged photo (the bytes and the draft reference), keeping the
    /// chosen kind so the composer stays on photo.
    func removeStagedPhoto(for questionID: UUID) {
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

    /// Clears a sent photo answer: removes the staged bytes and the whole draft.
    private func clearMediaDraft(for questionID: UUID) {
        mediaDraftStore.removeStagedMedia(instanceID: questionID)
        clearDraft(for: questionID)
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
