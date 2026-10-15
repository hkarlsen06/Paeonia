import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChallengeSubmitHandlerTests {
    @MainActor
    @Test func dailySubmitAnswerHandlerUploadsThenSubmits() async throws {
        let instanceID = UUID()
        let answerID = UUID()
        let assetID = UUID()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        try mediaStore.writeStagedMedia(Data([0x09, 0x09, 0x09]), instanceID: instanceID)

        let uploader = RecordingMediaUploadService(assetID: assetID)
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: uploader, gateway: gateway, mediaDraftStore: mediaStore
        )

        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: answerID,
            content: .media(
                DailySubmitAnswerOperationPayload.Media(
                    draft: DailyAnswerMediaDraft(
                        purpose: .photo, mimeType: "image/jpeg", fileExtension: "jpg", width: 10, height: 8,
                        durationMs: nil
                    ),
                    coupleID: TestDailyChallengeIDs.couple,
                    reserveOperation: dailyFixedClientOperation(),
                    finalizeOperation: dailyFixedClientOperation()
                )
            )
        )
        let operation = dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        #expect(result == .succeeded)
        #expect(await uploader.uploadCount == 1)
        #expect(await uploader.lastAnswerID == answerID)
        #expect(await uploader.lastCoupleID == TestDailyChallengeIDs.couple)
        #expect(await gateway.submittedPayloads == [DailyAnswerPayload(mediaAssetIDs: [assetID])])
        #expect(await gateway.submittedAnswerIDs == [answerID])
        // The staged copy is removed once the answer is sent.
        #expect(mediaStore.stagedMediaData(instanceID: instanceID) == nil)
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerRestoresQueuedMediaBytesWhenStagedFileMissing() async throws {
        let instanceID = UUID()
        let answerID = UUID()
        let assetID = UUID()
        let mediaStore = InMemoryDailyAnswerMediaDraftStore()
        let uploader = RecordingMediaUploadService(assetID: assetID)
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: uploader,
            gateway: gateway,
            mediaDraftStore: mediaStore
        )

        let queuedBytes = Data([0x07, 0x08, 0x09])
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: answerID,
            content: .media(
                DailySubmitAnswerOperationPayload.Media(
                    draft: DailyAnswerMediaDraft(
                        purpose: .voice,
                        mimeType: "audio/mp4",
                        fileExtension: "m4a",
                        width: nil,
                        height: nil,
                        durationMs: 1_200
                    ),
                    coupleID: TestDailyChallengeIDs.couple,
                    reserveOperation: dailyFixedClientOperation(),
                    finalizeOperation: dailyFixedClientOperation(),
                    stagedData: queuedBytes
                )
            )
        )
        let operation = dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        #expect(result == .succeeded)
        #expect(await uploader.uploadCount == 1)
        #expect(await gateway.submittedPayloads == [DailyAnswerPayload(mediaAssetIDs: [assetID])])
        #expect(mediaStore.stagedMediaData(instanceID: instanceID) == nil)
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerFailsTerminallyWhenStagedMediaMissing() async throws {
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: RecordingMediaUploadService(assetID: UUID()),
            gateway: RecordingDailyChallengeGateway(),
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore()
        )
        let payload = DailySubmitAnswerOperationPayload(
            instanceID: UUID(),
            answerID: UUID(),
            content: .media(
                DailySubmitAnswerOperationPayload.Media(
                    draft: DailyAnswerMediaDraft(
                        purpose: .photo,
                        mimeType: "image/jpeg",
                        fileExtension: "jpg",
                        width: 1,
                        height: 1,
                        durationMs: nil
                    ),
                    coupleID: TestDailyChallengeIDs.couple,
                    reserveOperation: dailyFixedClientOperation(),
                    finalizeOperation: dailyFixedClientOperation()
                )
            )
        )
        let operation = dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        if case .terminalFailure = result {
            // Expected: nothing to send once staged file and queued fallback are gone.
        } else {
            Issue.record("Expected terminal failure, got \(result)")
        }
    }

    @MainActor
    @Test func dailySubmitAnswerHandlerSubmitsTextWithoutUpload() async throws {
        let instanceID = UUID()
        let answerID = UUID()
        let uploader = RecordingMediaUploadService(assetID: UUID())
        let gateway = RecordingDailyChallengeGateway()
        let handler = DailySubmitAnswerPendingOperationHandler(
            mediaUploadService: uploader,
            gateway: gateway,
            mediaDraftStore: InMemoryDailyAnswerMediaDraftStore()
        )

        let payload = DailySubmitAnswerOperationPayload(
            instanceID: instanceID,
            answerID: answerID,
            content: .text("Thinking of you")
        )
        let operation = dailyPendingSnapshot(requestData: try JSONEncoder().encode(payload))

        let result = try await handler.send(operation, context: dailyChallengeSyncContext())

        #expect(result == .succeeded)
        // Text goes straight to the backend — no media upload step.
        #expect(await uploader.uploadCount == 0)
        #expect(await gateway.submittedPayloads == [DailyAnswerPayload(text: "Thinking of you")])
        #expect(await gateway.submittedAnswerIDs == [answerID])
    }
}
