import Foundation
import Testing
@testable import PaeoniaApp

/// Taking back a message that may have reached the server, and one the partner took back.
@MainActor
struct ThreadChatTakeBackTests {
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

    // MARK: - A send that may have reached the server

    /// Queues a message and marks it tried once, as after a network drop, then takes it back.
    private func takeBackATriedMessage(
        _ fixture: ChatTestFixture,
        service: ThreadChatService,
        body: String
    ) async throws -> (send: SyncClientOperation, message: ThreadChatMessage) {
        let send = fixture.operationProvider.makeOperation()
        let message = try await service.queueMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            subject: .question(fixture.question.questionID),
            threadID: fixture.threadID,
            body: body,
            photos: nil,
            createThread: false,
            replyTo: nil,
            operation: send
        )
        try await fixture.pendingStore.markSending(clientOperationID: send.id, at: Date())
        try await fixture.pendingStore.markRetryableFailure(
            clientOperationID: send.id,
            errorDescription: "The connection was lost",
            nextRetryAt: nil,
            at: Date()
        )
        try await service.deleteMessage(
            ownerUserID: fixture.ownerUserID,
            message: message,
            operation: fixture.operationProvider.makeOperation()
        )
        return (send, message)
    }

    @Test func aMessageTriedBeforeStaysInTheQueueAndItsDeleteWaitsBehindIt() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)

        let (send, _) = try await takeBackATriedMessage(fixture, service: service, body: "Maybe sent")

        // The server may already have it, so the send must run and the delete follow it.
        #expect(try await fixture.queuedOperations(.sendThreadMessage).map(\.operation.id) == [send.id])
        let deletes = try await fixture.queuedOperations(.deleteThreadMessage)
        let data = try #require(deletes.first?.requestData)
        let payload = try JSONDecoder().decode(DeleteChatMessagePayload.self, from: data)
        #expect(payload.target == .sentBy(operationID: send.id))
        #expect(await fixture.cachedMessages().isEmpty)
        #expect(await fixture.pendingMessages(service).isEmpty)
    }

    @Test func theServersCopyOfATakenBackMessageShowsAsDeletedBeforeTheDeleteRuns() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        _ = try await takeBackATriedMessage(fixture, service: service, body: "Maybe sent")
        await fixture.gateway.setRemote(
            summaries: [fixture.summary],
            messages: [fixture.ownServerCopy(body: "Maybe sent", at: 3)]
        )

        let refreshed = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID,
            threadID: fixture.threadID
        )

        #expect(refreshed.map(\.isDeleted) == [true])
        #expect(refreshed.first?.body.isEmpty == true)
    }

    @Test func aDeleteBehindASendWaitsForTheSendThenDeletesWhatTheServerMade() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        let (send, _) = try await takeBackATriedMessage(fixture, service: service, body: "Maybe sent")
        let delete = try #require(await fixture.queuedOperations(.deleteThreadMessage).first)
        let handler = DeleteChatMessageOperationHandler(gateway: fixture.gateway, cache: fixture.cache)
        let context = chatSyncContext(ownerUserID: fixture.ownerUserID, pendingStore: fixture.pendingStore)

        let whileSending = try await handler.send(delete, context: context)
        #expect(whileSending == .retry(after: nil))
        #expect(await fixture.gateway.deletedMessageIDs.isEmpty)

        await fixture.confirm(send, body: "Maybe sent")
        try await fixture.pendingStore.markSucceeded(clientOperationID: send.id, at: Date())
        let afterSend = try await handler.send(delete, context: context)

        #expect(afterSend == .succeeded)
        #expect(await fixture.gateway.deletedMessageIDs == [fixture.messageID])
        #expect(await fixture.cachedMessages().map(\.isDeleted) == [true])
    }

    @Test func aDeleteBehindASendThatNeverReachedTheServerHasNothingToDelete() async throws {
        let fixture = ChatTestFixture()
        let service = makeService(fixture)
        let (send, _) = try await takeBackATriedMessage(fixture, service: service, body: "Never arrived")
        try await fixture.pendingStore.markTerminalFailure(
            clientOperationID: send.id,
            errorDescription: "Refused",
            at: Date()
        )
        let delete = try #require(await fixture.queuedOperations(.deleteThreadMessage).first)
        let handler = DeleteChatMessageOperationHandler(gateway: fixture.gateway, cache: fixture.cache)

        let result = try await handler.send(
            delete,
            context: chatSyncContext(ownerUserID: fixture.ownerUserID, pendingStore: fixture.pendingStore)
        )

        #expect(result == .succeeded)
        #expect(await fixture.gateway.deletedMessageIDs.isEmpty)
    }

    // MARK: - A message the partner took back

    @Test func aTakenBackMessageNamedInAPushLosesItsTextAndFilesInTheCachedHistory() async throws {
        let fixture = ChatTestFixture()
        let evictions = EvictionRecorder()
        let service = makeService(fixture, mediaCache: evictions)
        let assetID = UUID()
        var old = fixture.partnerMessage(body: "Secret", id: fixture.messageID, at: 1)
        old.photos = [ThreadChatPhoto(mediaAssetID: assetID)]
        await fixture.cache.saveMessages(
            [old, fixture.partnerMessage(body: "Newer", at: 10)],
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID
        )

        await service.applyRemoteDeletion(ownerUserID: fixture.ownerUserID, messageID: fixture.messageID)

        let cached = await fixture.cachedMessages()
        #expect(cached.map(\.isDeleted) == [true, false])
        #expect(cached.first?.body.isEmpty == true)
        #expect(cached.first?.photos == nil)
        #expect(await evictions.evicted == [assetID])
    }

    @Test func anOlderCachedMessageDeletedWhileAwayIsReadAgainWhenTheChatOpens() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let old = fixture.partnerMessage(body: "Secret", at: 1)
        let current = fixture.partnerMessage(body: "Current", at: 10)
        await fixture.cache.saveMessages(
            [old, current], ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID
        )
        var gone = old.takenBack
        gone.deletedAt = Date(timeIntervalSince1970: 20)
        await fixture.gateway.setRemote(summaries: [fixture.summary], messages: [current])
        await fixture.gateway.setPageHasMore(true)
        await fixture.gateway.setOlderPages([
            ThreadChatMessagePage(messages: [gone], hasMore: false, oldestAt: gone.createdAt)
        ])

        let refreshed = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID,
            threadID: fixture.threadID
        )

        #expect(refreshed.map(\.isDeleted) == [true, false])
        #expect(refreshed.first?.body.isEmpty == true)
    }

    @Test func pastThePageLimitTheOlderCachedMessagesAreDroppedInsteadOfLeftUnchecked() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let oldest = fixture.partnerMessage(body: "Oldest", at: 0)
        let current = fixture.partnerMessage(body: "Current", at: 1_000)
        await fixture.cache.saveMessages(
            [oldest, current], ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID
        )
        await fixture.gateway.setRemote(summaries: [fixture.summary], messages: [current])
        await fixture.gateway.setPageHasMore(true)
        let pages = (1...ThreadChatService.revalidationPageLimit).map { index in
            let message = fixture.partnerMessage(body: "Page \(index)", at: 1_000 - Double(index))
            return ThreadChatMessagePage(messages: [message], hasMore: true, oldestAt: message.createdAt)
        }
        await fixture.gateway.setOlderPages(pages)

        let refreshed = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID,
            threadID: fixture.threadID
        )

        #expect(!refreshed.map(\.body).contains("Oldest"))
        #expect(refreshed.count == ThreadChatService.revalidationPageLimit + 1)
    }
}
