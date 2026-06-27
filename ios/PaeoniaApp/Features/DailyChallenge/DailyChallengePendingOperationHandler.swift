import Foundation

/// The persisted description of a queued media answer. Carries everything the
/// background handler needs to finish sending it: which question and answer, the
/// media's metadata (the bytes live in the staged-media store keyed by instance),
/// and the reserve/finalize operations so retries stay idempotent.
nonisolated struct DailySubmitAnswerOperationPayload: Codable, Sendable, Equatable {
    let instanceID: UUID
    let answerID: UUID
    let media: DailyAnswerMediaDraft
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
}

/// Finishes a staged media answer in the background: uploads the staged file, then
/// submits its asset id. Reused on every retry, so a flaky connection eventually
/// lands the answer without losing the photo. The reserve/finalize/submit operations
/// are fixed in the payload, so a retry never creates a duplicate asset or answer.
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

        guard let bytes = mediaDraftStore.stagedMediaData(instanceID: payload.instanceID) else {
            // The staged photo is gone (e.g. cleared on sign-out), so there's nothing
            // left to send. Fail terminally rather than retrying forever.
            return .terminalFailure("Staged media missing")
        }

        let uploadable = DailyAnswerUploadMedia(
            data: bytes,
            purpose: payload.media.purpose,
            mimeType: payload.media.mimeType,
            fileExtension: payload.media.fileExtension,
            width: payload.media.width,
            height: payload.media.height,
            durationMs: payload.media.durationMs
        )

        let assetID = try await mediaUploadService.uploadMedia(
            uploadable,
            answerID: payload.answerID,
            reserveOperation: payload.reserveOperation,
            finalizeOperation: payload.finalizeOperation
        )

        _ = try await gateway.submitAnswer(
            instanceID: payload.instanceID,
            answerID: payload.answerID,
            payload: .media([assetID]),
            operation: operation.operation
        )

        // The answer is sent; the staged copy is no longer needed.
        mediaDraftStore.removeStagedMedia(instanceID: payload.instanceID)
        return .succeeded
    }
}
