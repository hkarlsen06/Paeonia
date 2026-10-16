import Foundation
import Testing
@testable import PaeoniaApp

/// The chat cache keeps one file per question and holds what it read in memory.
struct DailyQuestionChatCacheFilesTests {
    private let owner = UUID()
    private let thread = UUID()
    private let couple = UUID()

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatCacheFiles-\(UUID().uuidString)", isDirectory: true)
    }

    private func ownerDirectory(_ directory: URL) -> URL {
        directory.appendingPathComponent(owner.uuidString.lowercased(), isDirectory: true)
    }

    private func fileNames(_ directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: ownerDirectory(directory).path)) ?? []
        return names.sorted()
    }

    private func message(_ question: UUID, _ body: String, at seconds: Double = 5) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: UUID(), threadID: thread, questionID: question, senderUserID: UUID(), body: body,
            createdAt: Date(timeIntervalSince1970: seconds), clientOperationID: nil, isSending: false
        )
    }

    private func summary(_ question: UUID, lastBody: String = "Hi") -> DailyQuestionThreadSummary {
        DailyQuestionThreadSummary(
            threadID: thread, coupleID: couple, questionID: question,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
            lastMessageID: nil, lastMessageAt: nil, lastMessageSenderUserID: nil, lastMessageBody: lastBody
        )
    }

    @Test func eachQuestionKeepsItsMessagesInItsOwnFile() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let first = UUID()
        let second = UUID()

        await cache.saveMessages([message(first, "One")], ownerUserID: owner, questionID: first)
        await cache.saveMessages([message(second, "Two")], ownerUserID: owner, questionID: second)

        let expected = ["question-\(first.uuidString).json", "question-\(second.uuidString).json"]
        #expect(fileNames(directory) == expected.sorted())
        let reopened = FileDailyQuestionChatCache(directoryURL: directory)
        #expect(await reopened.messages(ownerUserID: owner, questionID: first).map(\.body) == ["One"])
        #expect(await reopened.messages(ownerUserID: owner, questionID: second).map(\.body) == ["Two"])
    }

    @Test func aSaveThatChangesNothingWritesNothing() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let question = UUID()
        let saved = [message(question, "One")]
        await cache.saveMessages(saved, ownerUserID: owner, questionID: question)
        #expect(await cache.saveSummaries([summary(question)], ownerUserID: owner))
        try? FileManager.default.removeItem(at: ownerDirectory(directory))

        await cache.saveMessages(saved, ownerUserID: owner, questionID: question)
        let summaryChanged = await cache.saveSummaries([summary(question)], ownerUserID: owner)

        #expect(!summaryChanged)
        #expect(fileNames(directory).isEmpty)
    }

    @Test func aChangedSummaryIsReportedAndWritten() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let question = UUID()

        #expect(await cache.saveSummaries([summary(question)], ownerUserID: owner))
        #expect(await cache.saveSummaries([summary(question, lastBody: "Newer")], ownerUserID: owner))

        let reopened = FileDailyQuestionChatCache(directoryURL: directory)
        #expect(await reopened.summaries(ownerUserID: owner).first?.lastMessageBody == "Newer")
    }

    @Test func theCacheReadsAFileOnceAndThenAnswersFromMemory() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let question = UUID()
        await FileDailyQuestionChatCache(directoryURL: directory)
            .saveMessages([message(question, "One")], ownerUserID: owner, questionID: question)
        let cache = FileDailyQuestionChatCache(directoryURL: directory)

        #expect(await cache.messages(ownerUserID: owner, questionID: question).count == 1)
        try? FileManager.default.removeItem(at: ownerDirectory(directory))

        #expect(await cache.messages(ownerUserID: owner, questionID: question).count == 1)
    }

    @Test func aNewMessageRewritesOnlyItsQuestionAndTheSummaries() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let busy = UUID()
        let quiet = UUID()
        await cache.saveMessages([message(quiet, "Quiet")], ownerUserID: owner, questionID: quiet)
        let quietFile = ownerDirectory(directory).appendingPathComponent("question-\(quiet.uuidString).json")
        let before = try? Data(contentsOf: quietFile)
        try? FileManager.default.removeItem(at: quietFile)

        await cache.saveMessages([message(busy, "Busy")], ownerUserID: owner, questionID: busy)

        #expect(before != nil)
        #expect(!FileManager.default.fileExists(atPath: quietFile.path))
    }

    @Test func aFailedMessageIsFoundInAQuestionThatIsNotInMemory() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let question = UUID()
        let operation = UUID()
        let sending = DailyQuestionChatMessage(
            id: operation, threadID: nil, questionID: question, senderUserID: owner, body: "Hi",
            createdAt: Date(timeIntervalSince1970: 5), clientOperationID: operation, isSending: true
        )
        await FileDailyQuestionChatCache(directoryURL: directory).append(sending, ownerUserID: owner)
        let reopened = FileDailyQuestionChatCache(directoryURL: directory)

        await reopened.markFailed(ownerUserID: owner, clientOperationID: operation)

        let messages = await reopened.messages(ownerUserID: owner, questionID: question)
        #expect(messages.count == 1)
        #expect(messages.first?.sendFailed == true)
        await reopened.discardFailed(ownerUserID: owner, clientOperationID: operation)
        #expect(await reopened.messages(ownerUserID: owner, questionID: question).isEmpty)
    }

    @Test func seenPartnerAnswersKeepOnlyTheNewestOnes() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let limit = DailyChatCoreDocument.seenAnswerLimit
        let ids = (0..<(limit + 3)).map { _ in UUID() }

        for id in ids { await cache.markPartnerAnswerSeen(ownerUserID: owner, instanceID: id) }

        let seen = await cache.seenPartnerAnswers(ownerUserID: owner)
        #expect(seen.count == limit)
        #expect(!seen.contains(ids[0]))
        #expect(seen.contains(ids[3]))
        #expect(seen.contains(ids[limit + 2]))
    }

    @Test func olderMessagesJoinTheConfirmedOnesAndAPurgeStopsThem() async {
        let cache = InMemoryDailyQuestionChatCache()
        let question = UUID()
        let newest = message(question, "Newest", at: 20)
        let older = message(question, "Older", at: 10)
        let oldest = message(question, "Oldest", at: 1)
        await cache.saveMessages([newest, older], ownerUserID: owner, questionID: question)
        let generation = await cache.purgeGeneration()

        #expect(await cache.mergeOlderMessages(
            [oldest], ownerUserID: owner, questionID: question, unlessPurgedSince: generation
        ))
        let merged = await cache.messages(ownerUserID: owner, questionID: question)
        #expect(merged.map(\.body) == ["Oldest", "Older", "Newest"])

        await cache.clearAll()
        #expect(await !cache.mergeOlderMessages(
            [oldest], ownerUserID: owner, questionID: question, unlessPurgedSince: generation
        ))
        #expect(await cache.messages(ownerUserID: owner, questionID: question).isEmpty)
    }
}

/// The chat opens on the newest page and loads older pages when the person scrolls up.
@MainActor
struct DailyQuestionChatMessagePagingTests {
    private func page(
        _ messages: [DailyQuestionChatMessage],
        hasMore: Bool,
        oldestAt: Date? = nil
    ) -> DailyQuestionChatMessagePage {
        DailyQuestionChatMessagePage(
            messages: messages, hasMore: hasMore, oldestAt: oldestAt ?? messages.first?.createdAt
        )
    }

    @Test func aPageWithOlderMessagesKeepsTheCachedMessagesBeforeIt() {
        let fixture = ChatTestFixture()
        let old = fixture.partnerMessage(body: "Old", at: 1)
        let inPage = fixture.partnerMessage(body: "In page", at: 10)
        let newer = fixture.partnerMessage(body: "Newer", at: 11)
        let result = DailyQuestionChatMessage.keepingOlderCached(
            page([inPage, newer], hasMore: true), remote: [inPage, newer], cached: [old, inPage]
        )

        #expect(result.map(\.body).sorted() == ["In page", "Newer", "Old"])
    }

    @Test func aPageThatSkipsPastTheCacheReplacesItSoNoHoleRemains() {
        let fixture = ChatTestFixture()
        let old = fixture.partnerMessage(body: "Old", at: 1)
        let latest = fixture.partnerMessage(body: "Latest", at: 100)
        let result = DailyQuestionChatMessage.keepingOlderCached(
            page([latest], hasMore: true), remote: [latest], cached: [old]
        )

        #expect(result.map(\.body) == ["Latest"])
    }

    @Test func aPageThatReachesTheStartReplacesTheCachedMessages() {
        let fixture = ChatTestFixture()
        let removed = fixture.partnerMessage(body: "Removed", at: 1)
        let kept = fixture.partnerMessage(body: "Kept", at: 10)
        let result = DailyQuestionChatMessage.keepingOlderCached(
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
            [old, current], ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID
        )
        await fixture.gateway.setRemote(summaries: [fixture.summary], messages: [current])
        await fixture.gateway.setPageHasMore(true)

        let result = try await service.refreshMessages(
            ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID, threadID: fixture.threadID
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
            [old, current], ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID
        )
        let updates = service.liveMessageUpdates(
            ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID, threadID: fixture.threadID
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
            [newest, oldest], ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID
        )
        await fixture.gateway.setOlderPages([page([earlier], hasMore: true)])

        let hasMore = try await service.loadOlderMessages(
            ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID, threadID: fixture.threadID
        )

        #expect(hasMore)
        let cursor = DailyQuestionChatMessageCursor(createdAt: oldest.createdAt, messageID: oldest.id)
        #expect(await fixture.gateway.loadCursors == [cursor])
        #expect(await fixture.cachedMessages().map(\.body) == ["Earlier", "Oldest cached", "Newest"])
    }

    @Test func theLastPageEndsTheList() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        await fixture.cache.saveMessages(
            [fixture.partnerMessage(body: "Only", at: 10)],
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID
        )
        await fixture.gateway.setOlderPages([page([fixture.partnerMessage(body: "First", at: 1)], hasMore: false)])

        let hasMore = try await service.loadOlderMessages(
            ownerUserID: fixture.ownerUserID, questionID: fixture.question.questionID, threadID: fixture.threadID
        )

        #expect(!hasMore)
        #expect(await fixture.cachedMessages().count == 2)
    }

    @MainActor
    @Test func theChatOffersOlderMessagesUntilALoadReachesTheStart() async {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await viewModel.prepare()
        #expect(!viewModel.hasOlderMessages)

        // A few messages can still have older ones behind them, when newer ones were removed.
        await fixture.cache.saveMessages(
            [fixture.partnerMessage(body: "Latest", at: 10)],
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID
        )
        await viewModel.prepare()
        #expect(viewModel.hasOlderMessages)

        await fixture.gateway.setOlderPages([page([fixture.partnerMessage(body: "Start", at: 0)], hasMore: false)])
        await viewModel.loadOlderMessages()
        #expect(!viewModel.hasOlderMessages)
        #expect(viewModel.messages.first?.body == "Start")
    }
}
