import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatCacheRaceTests {
    @Test func claimingPendingKeepsTheOperationOfAMessageTheCacheAlreadyClaimed() {
        let owner = UUID()
        let question = UUID()
        let serverID = UUID()
        let operation = UUID()
        func message(_ id: UUID, operation: UUID? = nil, sending: Bool = false) -> DailyQuestionChatMessage {
            DailyQuestionChatMessage(
                id: id, threadID: nil, questionID: question, senderUserID: owner, body: "ok",
                createdAt: Date(timeIntervalSince1970: 3), clientOperationID: operation, isSending: sending
            )
        }
        let pending = message(operation, operation: operation, sending: true)

        let result = DailyQuestionChatMessage.claimingPending(
            remote: [message(serverID)],
            cached: [message(serverID, operation: operation)],
            pending: [pending]
        )

        #expect(result.first?.clientOperationID == operation)
        #expect(DailyQuestionChatMessage.visibleOrdered(remote: result, optimistic: [pending]).count == 1)
    }

    @Test func aLiveResultThatArrivesAfterAPurgeIsNotWrittenBack() async {
        let fixture = ChatTestFixture()
        let service = DailyQuestionChatService(
            gateway: fixture.gateway,
            cache: fixture.cache,
            pendingOperationStore: fixture.pendingStore
        )
        let updates = service.liveMessageUpdates(
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID,
            threadID: fixture.threadID
        )
        var iterator = updates.makeAsyncIterator()

        await fixture.gateway.liveSource.push([fixture.partnerMessage(body: "Before")])
        await iterator.next()
        #expect(await fixture.cachedMessages().count == 1)

        // Sign-out clears the cache. The subscription can still deliver one more result.
        await fixture.cache.clearAll()
        await fixture.gateway.liveSource.push([fixture.partnerMessage(body: "After")])

        #expect(await iterator.next() == nil)
        #expect(await fixture.cachedMessages().isEmpty)
    }

    @Test func theFileCacheRefusesAMessageSaveThatStartedBeforeAPurge() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatCachePurge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let fixture = ChatTestFixture()
        let message = fixture.partnerMessage(body: "Private")

        let started = await cache.purgeGeneration()
        await cache.clearAll()
        let wrote = await cache.saveMessages(
            [message],
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID,
            unlessPurgedSince: started
        )

        #expect(!wrote)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let current = await cache.purgeGeneration()
        #expect(await cache.saveMessages(
            [message],
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID,
            unlessPurgedSince: current
        ))
        let stored = await cache.messages(ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID)
        #expect(stored.count == 1)
    }

    @Test func claimingPendingMatchesTheOldestSendingMessageOnce() {
        let owner = UUID()
        let question = UUID()
        func message(
            _ id: UUID,
            _ body: String,
            at seconds: Double,
            operation: UUID? = nil,
            sending: Bool = false
        ) -> DailyQuestionChatMessage {
            DailyQuestionChatMessage(
                id: id, threadID: nil, questionID: question, senderUserID: owner, body: body,
                createdAt: Date(timeIntervalSince1970: seconds), clientOperationID: operation, isSending: sending
            )
        }
        let earlierServerID = UUID()
        let newServerID = UUID()
        let operation = UUID()
        // "ok" was sent earlier and is already known. Only the new server copy belongs to the sending one.
        let claimed = DailyQuestionChatMessage.claimingPending(
            remote: [message(earlierServerID, "ok", at: 1), message(newServerID, "ok", at: 9)],
            cached: [message(earlierServerID, "ok", at: 1)],
            pending: [message(operation, "ok", at: 8, operation: operation, sending: true)]
        )
        #expect(claimed.first(where: { $0.id == earlierServerID })?.clientOperationID == nil)
        #expect(claimed.first(where: { $0.id == newServerID })?.clientOperationID == operation)
    }

    @Test func aSlowRefreshDoesNotDropAMessageThatArrivedWhileItWasLoading() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let gateway = fixture.gateway
        let earlier = fixture.partnerMessage(body: "Earlier", at: 5)
        let justNow = fixture.partnerMessage(body: "Just now", at: 9)
        await gateway.setRemote(summaries: [fixture.summary], messages: [earlier])
        await gateway.holdLoads()
        let owner = fixture.ownerUserID
        let questionID = fixture.question.questionID
        let threadID = fixture.threadID

        let refresh = Task {
            try await service.refreshMessages(ownerUserID: owner, questionID: questionID, threadID: threadID)
        }
        #expect(await waitUntil { await gateway.loadCallCount == 1 })

        // The live result lands while the request is still out.
        let updates = service.liveMessageUpdates(ownerUserID: owner, questionID: questionID, threadID: threadID)
        var iterator = updates.makeAsyncIterator()
        await gateway.liveSource.push([earlier, justNow])
        await iterator.next()
        await gateway.releaseLoads()
        _ = try await refresh.value

        let cached = await fixture.cache.messages(ownerUserID: owner, questionID: questionID)
        #expect(cached.map(\.body) == ["Earlier", "Just now"])
    }

    @Test func refreshesThatFinishAfterAPurgeAreNotWrittenBack() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let gateway = fixture.gateway
        await gateway.setRemote(
            summaries: [fixture.summary],
            messages: [fixture.partnerMessage(body: "Private")]
        )
        await gateway.holdLoads()
        let owner = fixture.ownerUserID
        let questionID = fixture.question.questionID
        let threadID = fixture.threadID

        let summaries = Task { try await service.refreshThreadSummaries(ownerUserID: owner) }
        let messages = Task {
            try await service.refreshMessages(ownerUserID: owner, questionID: questionID, threadID: threadID)
        }
        #expect(await waitUntil { await gateway.loadCallCount == 2 })

        // Sign-out clears the cache while both requests are out.
        await fixture.cache.clearAll()
        await gateway.releaseLoads()
        let refreshedSummaries = try await summaries.value
        _ = try await messages.value

        #expect(refreshedSummaries.isEmpty)
        #expect(await fixture.cache.summaries(ownerUserID: owner).isEmpty)
        #expect(await fixture.cache.messages(ownerUserID: owner, questionID: questionID).isEmpty)
    }

    @Test func theFileCacheKeepsTheConfirmedCopyWhenTheSendingCopyArrivesLate() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatCacheAppend-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()

        // The send's confirmation can land before the queued message is added to the cache.
        await cache.confirm(
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID,
            coupleID: fixture.question.coupleID,
            clientOperationID: operation.id,
            threadID: fixture.threadID,
            messageID: fixture.messageID,
            body: "Hi",
            senderUserID: fixture.ownerUserID,
            createdAt: operation.localCreatedAt
        )
        await cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: nil,
                questionID: fixture.question.questionID,
                senderUserID: fixture.ownerUserID,
                body: "Hi",
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: fixture.ownerUserID
        )

        let messages = await cache.messages(ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID)
        #expect(messages.map(\.id) == [fixture.messageID])
        #expect(messages.first?.isSending == false)
    }

    @Test func theFileCacheDiscardsOnlyAFailedMessage() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatCacheDiscard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let fixture = ChatTestFixture()
        let failed = fixture.operationProvider.makeOperation()
        let sending = fixture.operationProvider.makeOperation()
        for operation in [failed, sending] {
            await cache.append(
                DailyQuestionChatMessage(
                    id: operation.id,
                    threadID: nil,
                    questionID: fixture.question.questionID,
                    senderUserID: fixture.ownerUserID,
                    body: "Hi",
                    createdAt: operation.localCreatedAt,
                    clientOperationID: operation.id,
                    isSending: true
                ),
                ownerUserID: fixture.ownerUserID
            )
        }
        await cache.markFailed(ownerUserID: fixture.ownerUserID, clientOperationID: failed.id)

        await cache.discardFailed(ownerUserID: fixture.ownerUserID, clientOperationID: sending.id)
        let afterSendingDiscard = await cache.messages(
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID
        )
        await cache.discardFailed(ownerUserID: fixture.ownerUserID, clientOperationID: failed.id)
        let afterFailedDiscard = await cache.messages(
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID
        )

        #expect(afterSendingDiscard.count == 2)
        #expect(afterFailedDiscard.map(\.id) == [sending.id])
    }
}
