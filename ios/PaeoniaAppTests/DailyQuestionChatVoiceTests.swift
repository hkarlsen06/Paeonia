import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatVoiceTests {
    private func queueVoice(_ fixture: ChatTestFixture, _ service: DailyQuestionChatService, data: Data) async throws {
        _ = try await service.queueVoiceMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            questionID: fixture.question.questionID,
            threadID: fixture.threadID,
            voice: DailyQuestionChatVoicePayload(
                messageID: fixture.messageID,
                data: data,
                durationMs: 1_500,
                reserveOperation: fixture.operationProvider.makeOperation(),
                finalizeOperation: fixture.operationProvider.makeOperation()
            ),
            createThread: false,
            replyToMessageID: nil,
            operation: fixture.operationProvider.makeOperation()
        )
    }

    @Test func aQueuedVoiceMessageUploadsItsRecordingAndSendsTheUpload() async throws {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let service = fixture.makeService()
        let recording = Data([1, 2, 3])
        try await queueVoice(fixture, service, data: recording)

        let pending = await fixture.pendingMessages(service)
        #expect(pending.map(\.id) == [fixture.messageID])
        #expect(pending.first?.voice?.data == recording)

        let assetID = UUID()
        let uploader = ChatVoiceUploader(assetID: assetID)
        let queued = try #require(try await fixture.queuedOperations(.sendThreadMessage).first)
        let result = try await SendDailyChatMessageOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache,
            mediaUploadService: uploader
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))

        #expect(result == .succeeded)
        #expect(await uploader.uploadedParentIDs == [fixture.messageID])
        #expect(await fixture.gateway.lastMediaAssetIDs == [assetID])
        let cached = await fixture.cachedMessages()
        #expect(cached.first?.isSending == false)
    }

    @Test func aConfirmedVoiceMessageKeepsPlayingFromThisPhone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatVoice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let owner = UUID()
        let operationID = UUID()
        let message = DailyQuestionChatMessage(
            id: UUID(), threadID: nil, questionID: UUID(), senderUserID: owner, body: "",
            createdAt: Date(timeIntervalSince1970: 1), clientOperationID: operationID, isSending: true,
            voice: DailyQuestionChatVoice(data: Data([7]), durationMs: 900)
        )
        await cache.append(message, ownerUserID: owner)

        await cache.confirm(
            ownerUserID: owner, questionID: message.questionID, coupleID: UUID(), clientOperationID: operationID,
            threadID: UUID(), messageID: message.id, body: "", senderUserID: owner, createdAt: message.createdAt
        )

        let confirmed = try #require(await cache.messages(ownerUserID: owner, questionID: message.questionID).first)
        #expect(!confirmed.isSending)
        #expect(confirmed.voice == message.voice)
    }

    @Test func aPhotoMessageUploadsEachPhotoAsAChatPhotoAndSendsThemInOrder() async throws {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Earlier")],
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.prepare()
        let photos = [
            DailyQuestionChatPhoto(data: Data([1]), width: 400, height: 300),
            DailyQuestionChatPhoto(data: Data([2]), width: 300, height: 400),
        ]

        #expect(await viewModel.send("Look", photos: photos))
        let pending = viewModel.messages.last
        #expect(pending?.photos?.map(\.data) == [Data([1]), Data([2])])
        #expect(pending?.body == "Look")

        let uploader = ChatVoiceUploader(assetID: UUID())
        let queued = try #require(try await fixture.queuedOperations(.sendThreadMessage).first)
        let result = try await SendDailyChatMessageOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache,
            mediaUploadService: uploader
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))

        #expect(result == .succeeded)
        #expect(await uploader.uploadedPurposes == [.threadPhoto, .threadPhoto])
        // Both photos are reserved under the message's own id, which the server requires.
        let parentIDs = await uploader.uploadedParentIDs
        #expect(Set(parentIDs).count == 1)
        #expect(parentIDs.first == pending?.id)
        #expect(await fixture.gateway.lastMediaAssetIDs?.count == 2)
    }

    @Test func theServerCopyOfAVoiceMessageIsMatchedByItsID() {
        let me = UUID()
        func pendingVoice(_ id: UUID) -> DailyQuestionChatMessage {
            DailyQuestionChatMessage(
                id: id, threadID: nil, questionID: UUID(), senderUserID: me, body: "",
                createdAt: Date(timeIntervalSince1970: 1), clientOperationID: UUID(), isSending: true,
                voice: DailyQuestionChatVoice(data: Data([1]))
            )
        }
        let first = pendingVoice(UUID())
        let second = pendingVoice(UUID())
        let remoteSecond = DailyQuestionChatMessage(
            id: second.id, threadID: UUID(), questionID: second.questionID, senderUserID: me, body: "",
            createdAt: Date(timeIntervalSince1970: 2), clientOperationID: nil, isSending: false,
            voice: DailyQuestionChatVoice(mediaAssetID: UUID())
        )

        let claimed = DailyQuestionChatMessage.claimingPending(
            remote: [remoteSecond],
            cached: [],
            pending: [first, second]
        )

        #expect(claimed.first?.clientOperationID == second.clientOperationID)
    }
}
