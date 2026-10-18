import Foundation

/// The persisted description of a queued daily answer. Carries everything the
/// background handler needs to finish sending it after a network blip or while
/// offline: which question and answer, and the answer content itself.
///
/// Text and partner-choice answers submit straight to the backend. A media answer
/// keeps its bytes in the staged-media store (keyed by instance) and carries the
/// reserve/finalize operations so a retry never creates a duplicate asset.
nonisolated struct DailySubmitAnswerOperationPayload: Codable, Sendable, Equatable {
    let instanceID: UUID
    let answerID: UUID
    let content: Content
    /// Set for an answer to a topic question, which goes to `topics:submit_topic_answer`.
    /// Its `instanceID` is the topic instance id both phones derive (`TopicInstanceID`).
    var topicQuestionID: UUID?

    /// What the queued answer is sending. The combined cases let one answer carry a
    /// text caption alongside a photo or a partner pick (kept as separate cases so
    /// already-queued single-kind operations still decode after an app update).
    nonisolated enum Content: Codable, Sendable, Equatable {
        case text(String)
        case partnerChoice(UUID)
        case media(Media)
        case textAndMedia(String, Media)
        case textAndPartnerChoice(String, UUID)
        /// A pick-one-of-two answer, alone or with its why line.
        case optionChoice(DailyAnswerOption)
        case textAndOptionChoice(String, DailyAnswerOption)

        /// The editable draft this answer came from, so an answer the server refuses
        /// for good can go back into the composer instead of disappearing.
        var restoredDraft: DailyAnswerDraft {
            switch self {
            case let .text(body):
                DailyAnswerDraft(text: body)
            case let .partnerChoice(userID):
                DailyAnswerDraft(partnerChoiceUserID: userID, selectedKind: .partnerChoice)
            case let .media(media):
                DailyAnswerDraft(selectedKind: media.draft.purpose == .voice ? .voice : .photo, media: media.draft)
            case let .textAndMedia(body, media):
                DailyAnswerDraft(text: body, media: media.draft)
            case let .textAndPartnerChoice(body, userID):
                DailyAnswerDraft(text: body, partnerChoiceUserID: userID)
            case let .optionChoice(option):
                DailyAnswerDraft(optionChoice: option)
            case let .textAndOptionChoice(body, option):
                DailyAnswerDraft(text: body, optionChoice: option)
            }
        }
    }

    /// The staged-media details a queued photo/voice answer needs to upload. The
    /// reserve/finalize operations are fixed here so retries stay idempotent, and
    /// the couple id scopes the upload (the reserve RPC requires it for couple media).
    nonisolated struct Media: Codable, Sendable, Equatable {
        let draft: DailyAnswerMediaDraft
        let coupleID: UUID
        let reserveOperation: SyncClientOperation
        let finalizeOperation: SyncClientOperation
        /// Fallback copy of the staged bytes. The staged file is still the
        /// normal upload source, but this keeps media answers recoverable if
        /// the file is unavailable after a relaunch.
        let stagedData: Data?

        init(
            draft: DailyAnswerMediaDraft,
            coupleID: UUID,
            reserveOperation: SyncClientOperation,
            finalizeOperation: SyncClientOperation,
            stagedData: Data? = nil
        ) {
            self.draft = draft
            self.coupleID = coupleID
            self.reserveOperation = reserveOperation
            self.finalizeOperation = finalizeOperation
            self.stagedData = stagedData
        }
    }
}

/// Finishes a queued daily answer in the background. Text and partner-choice answers
/// submit directly; a media answer uploads its staged file first, then submits the
/// asset id. Reused on every retry, so a flaky connection eventually lands the answer
/// without losing it. The answer id (and, for media, the reserve/finalize/submit
/// operations) are fixed in the payload, so a retry never creates a duplicate answer
/// or asset.
struct DailySubmitAnswerPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitDailyAnswer

    /// Puts a refused answer back into the owner's drafts.
    typealias DraftRestorer = @Sendable (
        _ ownerUserID: UUID,
        _ instanceID: UUID,
        _ draft: DailyAnswerDraft
    ) async -> Void

    private let mediaUploadService: any DailyAnswerMediaUploading
    private let gateway: any DailyChallengeGateway
    private let mediaDraftStore: any DailyAnswerMediaDraftStoring
    private let restoreDraft: DraftRestorer

    init(
        mediaUploadService: any DailyAnswerMediaUploading,
        gateway: any DailyChallengeGateway,
        mediaDraftStore: any DailyAnswerMediaDraftStoring,
        restoreDraft: @escaping DraftRestorer = Self.restoreToSharedDraftStore
    ) {
        self.mediaUploadService = mediaUploadService
        self.gateway = gateway
        self.mediaDraftStore = mediaDraftStore
        self.restoreDraft = restoreDraft
    }

    nonisolated static func restoreToSharedDraftStore(
        ownerUserID: UUID,
        instanceID: UUID,
        draft: DailyAnswerDraft
    ) async {
        // The drain then marks the operation failed and posts `.pendingOperations`,
        // which tells an open daily challenge screen to pick the draft back up.
        await MainActor.run {
            UserDefaultsDailyChallengeDraftStore.shared.setDraft(draft, for: instanceID, userID: ownerUserID)
        }
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing daily answer payload")
        }

        let payload = try JSONDecoder().decodeQueuedPayload(DailySubmitAnswerOperationPayload.self, from: requestData)

        switch payload.content {
        case let .text(body):
            return try await submit(DailyAnswerPayload(text: body), payload: payload, operation: operation)
        case let .partnerChoice(userID):
            return try await submit(
                DailyAnswerPayload(partnerChoiceUserID: userID),
                payload: payload,
                operation: operation
            )
        case let .media(media):
            return try await sendMedia(media, text: nil, payload: payload, operation: operation)
        case let .textAndMedia(body, media):
            return try await sendMedia(media, text: body, payload: payload, operation: operation)
        case let .textAndPartnerChoice(body, userID):
            return try await submit(
                DailyAnswerPayload(text: body, partnerChoiceUserID: userID),
                payload: payload,
                operation: operation
            )
        case let .optionChoice(option):
            return try await submit(DailyAnswerPayload(optionChoice: option), payload: payload, operation: operation)
        case let .textAndOptionChoice(body, option):
            return try await submit(
                DailyAnswerPayload(text: body, optionChoice: option),
                payload: payload,
                operation: operation
            )
        }
    }

    nonisolated var showsGivenUpWrites: Bool { true }

    func gaveUp(on operation: PendingSyncOperationSnapshot, context _: SyncContext) async {
        // The answer goes back into the drafts, like a refused one, so nothing is lost.
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: data)
        else { return }
        await restoreDraft(operation.ownerUserID, payload.instanceID, payload.content.restoredDraft)
    }

    /// Uploads the staged bytes for a media answer, then submits the resulting asset
    /// (with an optional text caption alongside it). If the staged file is unavailable
    /// after relaunch, falls back to the copy embedded in the queued operation and
    /// restages it for later retries.
    private func sendMedia(
        _ media: DailySubmitAnswerOperationPayload.Media,
        text: String?,
        payload: DailySubmitAnswerOperationPayload,
        operation: PendingSyncOperationSnapshot
    ) async throws -> PendingSyncOperationSendResult {
        guard let bytes = restorableMediaData(media, instanceID: payload.instanceID) else {
            return .terminalFailure("Staged media missing")
        }

        let uploadable = DailyAnswerUploadMedia(
            data: bytes,
            purpose: media.draft.purpose,
            mimeType: media.draft.mimeType,
            fileExtension: media.draft.fileExtension,
            width: media.draft.width,
            height: media.draft.height,
            durationMs: media.draft.durationMs
        )

        let assetID = try await mediaUploadService.uploadMedia(
            uploadable,
            answerID: payload.answerID,
            coupleID: media.coupleID,
            reserveOperation: media.reserveOperation,
            finalizeOperation: media.finalizeOperation
        )

        let result = try await submit(
            DailyAnswerPayload(text: text, mediaAssetIDs: [assetID]),
            payload: payload,
            operation: operation
        )

        // Once sent, the staged copy is no longer needed. A refused answer keeps it,
        // because its draft points at it again.
        if result == .succeeded {
            mediaDraftStore.removeStagedMedia(instanceID: payload.instanceID)
        }
        return result
    }

    private func restorableMediaData(
        _ media: DailySubmitAnswerOperationPayload.Media,
        instanceID: UUID
    ) -> Data? {
        if let stagedData = mediaDraftStore.stagedMediaData(instanceID: instanceID) {
            return stagedData
        }

        guard let stagedData = media.stagedData else {
            return nil
        }

        try? mediaDraftStore.writeStagedMedia(stagedData, instanceID: instanceID)
        return stagedData
    }

    /// Submits the answer. When the server refuses it for good (for example its day
    /// ended, or it no longer fits the question), retrying would only keep it showing
    /// as "sending" forever. The operation stops instead, and the answer goes back
    /// into the drafts so nothing the user wrote is lost. Upload errors are not
    /// classified here and keep retrying.
    private func submit(
        _ answer: DailyAnswerPayload,
        payload: DailySubmitAnswerOperationPayload,
        operation: PendingSyncOperationSnapshot
    ) async throws -> PendingSyncOperationSendResult {
        do {
            if let topicQuestionID = payload.topicQuestionID {
                try await gateway.submitTopicAnswer(
                    questionID: topicQuestionID,
                    instanceID: payload.instanceID,
                    answerID: payload.answerID,
                    payload: answer,
                    operation: operation.operation
                )
            } else {
                _ = try await gateway.submitAnswer(
                    instanceID: payload.instanceID,
                    answerID: payload.answerID,
                    payload: answer,
                    operation: operation.operation
                )
            }
            return .succeeded
        } catch let error as PaeoniaConvexError where Self.isPermanentRejection(error) {
            await restoreDraft(operation.ownerUserID, payload.instanceID, payload.content.restoredDraft)
            return .terminalFailure(error.description)
        }
    }

    /// Server rejections that a retry can never fix: a check failed (`23514`, such as
    /// an answer made after its day ended), the operation was replayed with different
    /// content (`23505`), or the question no longer exists (`22023`). Access errors
    /// (`42501`) keep retrying, because access can come back.
    nonisolated static func isPermanentRejection(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return ["23514", "23505", "22023"].contains(code)
    }
}
