import Foundation
import Testing
@testable import PaeoniaApp

/// The chat cache keeps failed messages, seen answers and older pages on the phone.
struct ThreadChatCacheFilesTests {
    private let owner = UUID()
    private let thread = UUID()

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatCacheFiles-\(UUID().uuidString)", isDirectory: true)
    }

    private func message(_ question: UUID, _ body: String, at seconds: Double = 5) -> ThreadChatMessage {
        ThreadChatMessage(
            id: UUID(), threadID: thread, subjectID: question, senderUserID: UUID(), body: body,
            createdAt: Date(timeIntervalSince1970: seconds), clientOperationID: nil, isSending: false
        )
    }

    @Test func aFailedMessageIsFoundInAQuestionThatIsNotInMemory() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let question = UUID()
        let operation = UUID()
        let sending = ThreadChatMessage(
            id: operation, threadID: nil, subjectID: question, senderUserID: owner, body: "Hi",
            createdAt: Date(timeIntervalSince1970: 5), clientOperationID: operation, isSending: true
        )
        await FileThreadChatCache(directoryURL: directory).append(sending, ownerUserID: owner)
        let reopened = FileThreadChatCache(directoryURL: directory)

        await reopened.markFailed(ownerUserID: owner, clientOperationID: operation)

        let messages = await reopened.messages(ownerUserID: owner, subjectID: question)
        #expect(messages.count == 1)
        #expect(messages.first?.sendFailed == true)
        await reopened.discardFailed(ownerUserID: owner, clientOperationID: operation)
        #expect(await reopened.messages(ownerUserID: owner, subjectID: question).isEmpty)
    }

    @Test func seenPartnerAnswersKeepOnlyTheNewestOnes() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileThreadChatCache(directoryURL: directory)
        let limit = ThreadChatCoreDocument.seenAnswerLimit
        let ids = (0..<(limit + 3)).map { _ in UUID() }

        for id in ids { await cache.markPartnerAnswerSeen(ownerUserID: owner, instanceID: id) }

        let seen = await cache.seenPartnerAnswers(ownerUserID: owner)
        #expect(seen.count == limit)
        #expect(!seen.contains(ids[0]))
        #expect(seen.contains(ids[3]))
        #expect(seen.contains(ids[limit + 2]))
    }

    @Test func olderMessagesJoinTheConfirmedOnesAndAPurgeStopsThem() async {
        let cache = InMemoryThreadChatCache()
        let question = UUID()
        let newest = message(question, "Newest", at: 20)
        let older = message(question, "Older", at: 10)
        let oldest = message(question, "Oldest", at: 1)
        await cache.saveMessages([newest, older], ownerUserID: owner, subjectID: question)
        let generation = await cache.purgeGeneration()

        #expect(await cache.mergeOlderMessages(
            [oldest], ownerUserID: owner, subjectID: question, unlessPurgedSince: generation
        ))
        let merged = await cache.messages(ownerUserID: owner, subjectID: question)
        #expect(merged.map(\.body) == ["Oldest", "Older", "Newest"])

        await cache.clearAll()
        #expect(await !cache.mergeOlderMessages(
            [oldest], ownerUserID: owner, subjectID: question, unlessPurgedSince: generation
        ))
        #expect(await cache.messages(ownerUserID: owner, subjectID: question).isEmpty)
    }
}

/// The chat opens on the newest page and loads older pages when the person scrolls up.
@MainActor
struct ThreadChatMessagePagingTests {
    private func page(
        _ messages: [ThreadChatMessage],
        hasMore: Bool,
        oldestAt: Date? = nil
    ) -> ThreadChatMessagePage {
        ThreadChatMessagePage(
            messages: messages, hasMore: hasMore, oldestAt: oldestAt ?? messages.first?.createdAt
        )
    }

    @Test func aPageWithOlderMessagesKeepsTheCachedMessagesBeforeIt() {
        let fixture = ChatTestFixture()
        let old = fixture.partnerMessage(body: "Old", at: 1)
        let inPage = fixture.partnerMessage(body: "In page", at: 10)
        let newer = fixture.partnerMessage(body: "Newer", at: 11)
        let result = ThreadChatMessage.keepingOlderCached(
            page([inPage, newer], hasMore: true), remote: [inPage, newer], cached: [old, inPage]
        )

        #expect(result.map(\.body).sorted() == ["In page", "Newer", "Old"])
    }

    @Test func aPageThatSkipsPastTheCacheReplacesItSoNoHoleRemains() {
        let fixture = ChatTestFixture()
        let old = fixture.partnerMessage(body: "Old", at: 1)
        let latest = fixture.partnerMessage(body: "Latest", at: 100)
        let result = ThreadChatMessage.keepingOlderCached(
            page([latest], hasMore: true), remote: [latest], cached: [old]
        )

        #expect(result.map(\.body) == ["Latest"])
    }

    @Test func aPageThatReachesTheStartReplacesTheCachedMessages() {
        let fixture = ChatTestFixture()
        let removed = fixture.partnerMessage(body: "Removed", at: 1)
        let kept = fixture.partnerMessage(body: "Kept", at: 10)
        let result = ThreadChatMessage.keepingOlderCached(
            page([kept], hasMore: false), remote: [kept], cached: [removed, kept]
        )

        #expect(result.map(\.body) == ["Kept"])
    }

    @Test func aRefreshKeepsOlderMessagesLoadedBefore() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let old = fixture.partnerMessage(body: "Old", at: 1)
        let current = fixture.partnerMessage(body: "Current", at: 10)
        await fixture.cache.saveMessages(
            [old, current], ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID
        )
        await fixture.gateway.setRemote(summaries: [fixture.summary], messages: [current])
        await fixture.gateway.setPageHasMore(true)

        let result = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID, threadID: fixture.threadID
        )

        #expect(result.map(\.body) == ["Old", "Current"])
    }

    @Test func aLiveResultKeepsOlderMessagesLoadedBefore() async {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let old = fixture.partnerMessage(body: "Old", at: 1)
        let current = fixture.partnerMessage(body: "Current", at: 10)
        let arrived = fixture.partnerMessage(body: "Arrived", at: 11)
        await fixture.cache.saveMessages(
            [old, current], ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID
        )
        let updates = service.liveMessageUpdates(
            ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID, threadID: fixture.threadID
        )
        var iterator = updates.makeAsyncIterator()

        await fixture.gateway.liveSource.push(page([current, arrived], hasMore: true))
        await iterator.next()

        #expect(await fixture.cachedMessages().map(\.body) == ["Old", "Current", "Arrived"])
    }

    @Test func loadingOlderMessagesAsksForThePageBeforeTheOldestOnThePhone() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let oldest = fixture.partnerMessage(body: "Oldest cached", at: 10)
        let newest = fixture.partnerMessage(body: "Newest", at: 20)
        let earlier = fixture.partnerMessage(body: "Earlier", at: 5)
        await fixture.cache.saveMessages(
            [newest, oldest], ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID
        )
        await fixture.gateway.setOlderPages([page([earlier], hasMore: true)])

        let hasMore = try await service.loadOlderMessages(
            ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID, threadID: fixture.threadID
        )

        #expect(hasMore)
        let cursor = ThreadChatMessageCursor(createdAt: oldest.createdAt, messageID: oldest.id)
        #expect(await fixture.gateway.loadCursors == [cursor])
        #expect(await fixture.cachedMessages().map(\.body) == ["Earlier", "Oldest cached", "Newest"])
    }

    @Test func theLastPageEndsTheList() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        await fixture.cache.saveMessages(
            [fixture.partnerMessage(body: "Only", at: 10)],
            ownerUserID: fixture.ownerUserID,
            subjectID: fixture.question.questionID
        )
        await fixture.gateway.setOlderPages([page([fixture.partnerMessage(body: "First", at: 1)], hasMore: false)])

        let hasMore = try await service.loadOlderMessages(
            ownerUserID: fixture.ownerUserID, subjectID: fixture.question.questionID, threadID: fixture.threadID
        )

        #expect(!hasMore)
        #expect(await fixture.cachedMessages().count == 2)
    }
}
