import Foundation
import Testing
@testable import PaeoniaApp

/// Records which cached media files the chat asked to remove.
actor EvictionRecorder: DailyAnswerMediaCacheEvicting {
    private(set) var evicted: [UUID] = []

    func evict(mediaAssetIDs: [UUID]) {
        evicted.append(contentsOf: mediaAssetIDs)
    }
}

@MainActor
struct ThreadChatDeleteTests {
    private func ownSentMessage(_ fixture: ChatTestFixture, photoAssetID: UUID? = nil) -> ThreadChatMessage {
        var message = fixture.ownServerCopy(body: "Oops", at: 3)
        if let photoAssetID { message.photos = [ThreadChatPhoto(mediaAssetID: photoAssetID)] }
        return message
    }

    private func makeService(
        _ fixture: ChatTestFixture,
        mediaCache: (any DailyAnswerMediaCacheEvicting)? = nil
    ) -> ThreadChatService {
        ThreadChatService(
            gateway: fixture.gateway,
            cache: fixture.cache,
            pendingOperationStore: fixture.pendingStore,
            mediaCache: mediaCache
        )
    }

    @Test func aSentMessageShowsAsDeletedAtOnceAndTheDeleteWaitsInTheQueue() async throws {
        let fixture = ChatTestFixture()
        let evictions = EvictionRecorder()
        let service = makeService(fixture, mediaCache: evictions)
        let assetID = UUID()
        let message = ownSentMessage(fixture, photoAssetID: assetID)
        await fixture.cache.saveMessages([message], ownerUserID: fixture.ownerUserID, subjectID: message.subjectID)

        try await service.deleteMessage(
            ownerUserID: fixture.ownerUserID,
            message: message,
            operation: fixture.operationProvider.makeOperation()
        )

        let shown = try #require(await fixture.cachedMessages().first)
        #expect(shown.isDeleted)
        #expect(shown.body.isEmpty)
        #expect(shown.photos == nil)
        let queued = try await fixture.queuedOperations(.deleteThreadMessage)
        #expect(queued.count == 1)
        #expect(await evictions.evicted == [assetID])
    }

    @Test func aServerResultThatStillShowsTheMessageDoesNotBringItBack() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        let message = ownSentMessage(fixture)
        await fixture.cache.saveMessages([message], ownerUserID: fixture.ownerUserID, subjectID: message.subjectID)
        try await service.deleteMessage(
            ownerUserID: fixture.ownerUserID,
            message: message,
            operation: fixture.operationProvider.makeOperation()
        )
        await fixture.gateway.setRemote(summaries: [fixture.summary], messages: [message])

        let refreshed = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID,
            subjectID: message.subjectID,
            threadID: fixture.threadID
        )

        #expect(refreshed.map(\.isDeleted) == [true])
    }

    @Test func aMessageThePartnerTookBackLeavesTheFilesOnThisPhone() async throws {
        let fixture = ChatTestFixture()
        let evictions = EvictionRecorder()
        let service = makeService(fixture, mediaCache: evictions)
        let assetID = UUID()
        let shown = fixture.partnerMessage(body: "", id: fixture.messageID)
        var withPhoto = shown
        withPhoto.photos = [ThreadChatPhoto(mediaAssetID: assetID)]
        await fixture.cache.saveMessages([withPhoto], ownerUserID: fixture.ownerUserID, subjectID: shown.subjectID)
        var gone = shown
        gone.deletedAt = Date(timeIntervalSince1970: 9)
        await fixture.gateway.setRemote(summaries: [fixture.summary], messages: [gone])

        _ = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID,
            subjectID: shown.subjectID,
            threadID: fixture.threadID
        )

        #expect(await evictions.evicted == [assetID])
        #expect(await fixture.cachedMessages().map(\.isDeleted) == [true])
    }

    @Test func aMessageStillWaitingToSendIsPulledFromTheQueueAndNeverSent() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        let sending = try await service.queueMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            subject: .question(fixture.question.questionID),
            threadID: fixture.threadID,
            body: "Wrong chat",
            photos: nil,
            createThread: false,
            replyTo: nil,
            operation: fixture.operationProvider.makeOperation()
        )

        try await service.deleteMessage(
            ownerUserID: fixture.ownerUserID,
            message: sending,
            operation: fixture.operationProvider.makeOperation()
        )

        #expect(try await fixture.queuedOperations(.sendThreadMessage).isEmpty)
        #expect(try await fixture.queuedOperations(.deleteThreadMessage).isEmpty)
        #expect(await fixture.cachedMessages().isEmpty)
    }

    @Test func aMessageThatIsSendingRightNowCannotBeTakenBackYet() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        let sending = try await service.queueMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            subject: .question(fixture.question.questionID),
            threadID: fixture.threadID,
            body: "On its way",
            photos: nil,
            createThread: false,
            replyTo: nil,
            operation: fixture.operationProvider.makeOperation()
        )
        try await fixture.pendingStore.markSending(clientOperationID: sending.id, at: Date())

        await #expect(throws: ThreadChatServiceError.stillSending) {
            try await service.deleteMessage(
                ownerUserID: fixture.ownerUserID,
                message: sending,
                operation: fixture.operationProvider.makeOperation()
            )
        }
        #expect(try await fixture.queuedOperations(.sendThreadMessage).count == 1)
        #expect(await fixture.cachedMessages().map(\.isSending) == [true])
    }

    @Test func theFirstMessageStaysWhileLaterMessagesWaitForItsChat() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        let first = try await service.queueMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            subject: .question(fixture.question.questionID),
            threadID: nil,
            body: "First",
            photos: nil,
            createThread: true,
            replyTo: nil,
            operation: fixture.operationProvider.makeOperation()
        )
        _ = try await service.queueMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            subject: .question(fixture.question.questionID),
            threadID: nil,
            body: "Second",
            photos: nil,
            createThread: false,
            replyTo: nil,
            operation: fixture.operationProvider.makeOperation()
        )

        await #expect(throws: ThreadChatServiceError.stillSending) {
            try await service.deleteMessage(
                ownerUserID: fixture.ownerUserID,
                message: first,
                operation: fixture.operationProvider.makeOperation()
            )
        }
        #expect(try await fixture.queuedOperations(.createChatThreadWithMessage).count == 1)
    }

    @Test func theQueuedDeleteReachesTheServerAndARefusalIsFinal() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        let payload = DeleteChatMessagePayload(
            subjectID: fixture.question.questionID,
            target: .message(fixture.messageID)
        )
        let snapshot = chatPendingSnapshot(
            ownerUserID: fixture.ownerUserID,
            operation: operation,
            kind: .deleteThreadMessage,
            payload: try JSONEncoder().encode(payload)
        )
        let handler = DeleteChatMessageOperationHandler(gateway: fixture.gateway, cache: fixture.cache)
        let context = chatSyncContext(ownerUserID: fixture.ownerUserID, pendingStore: fixture.pendingStore)

        let sent = try await handler.send(snapshot, context: context)
        #expect(await fixture.gateway.deletedMessageIDs == [fixture.messageID])
        #expect(sent == .succeeded)

        await fixture.gateway.setDeleteError(
            PaeoniaConvexError.server(code: "42501", message: "only the sender can delete a message")
        )
        let refused = try await handler.send(snapshot, context: context)
        var isTerminal = false
        if case .terminalFailure = refused { isTerminal = true }
        #expect(isTerminal)

        await fixture.gateway.setDeleteError(ChatTestError.requested)
        await #expect(throws: ChatTestError.self) { try await handler.send(snapshot, context: context) }
    }

    @Test func onlyYourOwnMessageCanBeTakenBack() {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let own = ownSentMessage(fixture)
        var gone = own
        gone.deletedAt = .now

        #expect(viewModel.canDelete(own))
        #expect(!viewModel.canDelete(fixture.partnerMessage(body: "Hi")))
        #expect(!viewModel.canDelete(gone))
    }
}
