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

    /// What the queued answer is sending.
    nonisolated enum Content: Codable, Sendable, Equatable {
        case text(String)
        case partnerChoice(UUID)
        case media(Media)
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

    private let mediaUploadService: any DailyAnswerMediaUploading
    private let gateway: any SupabaseDailyChallengeGateway
    private let mediaDraftStore: any DailyAnswerMediaDraftStoring

    init(
        mediaUploadService: any DailyAnswerMediaUploading,
        gateway: any SupabaseDailyChallengeGateway,
        mediaDraftStore: any DailyAnswerMediaDraftStoring
    ) {
        self.mediaUploadService = mediaUploadService
        self.gateway = gateway
        self.mediaDraftStore = mediaDraftStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing daily answer payload")
        }

        let payload = try JSONDecoder().decode(DailySubmitAnswerOperationPayload.self, from: requestData)

        switch payload.content {
        case let .text(body):
            try await submit(.text(body), payload: payload, operation: operation)
            return .succeeded
        case let .partnerChoice(userID):
            try await submit(.partnerChoice(userID), payload: payload, operation: operation)
            return .succeeded
        case let .media(media):
            return try await sendMedia(media, payload: payload, operation: operation)
        }
    }

    /// Uploads the staged bytes for a media answer, then submits the resulting asset.
    /// If the staged file is unavailable after relaunch, falls back to the
    /// copy embedded in the queued operation and restages it for later retries.
    private func sendMedia(
        _ media: DailySubmitAnswerOperationPayload.Media,
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

        try await submit(.media([assetID]), payload: payload, operation: operation)

        // The answer is sent; the staged copy is no longer needed.
        mediaDraftStore.removeStagedMedia(instanceID: payload.instanceID)
        return .succeeded
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

    private func submit(
        _ answer: DailyAnswerPayload,
        payload: DailySubmitAnswerOperationPayload,
        operation: PendingSyncOperationSnapshot
    ) async throws {
        _ = try await gateway.submitAnswer(
            instanceID: payload.instanceID,
            answerID: payload.answerID,
            payload: answer,
            operation: operation.operation
        )
    }
}
