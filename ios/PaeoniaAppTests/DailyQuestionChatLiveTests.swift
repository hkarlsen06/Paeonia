import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatLiveTests {
    @Test func partnerMessageAppearsWhileTheChatIsOpenAndIsCached() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }

        await fixture.gateway.liveSource.push([fixture.partnerMessage(body: "Thinking of you")])

        let appeared = await waitForMain { viewModel.messages.map(\.body) == ["Thinking of you"] }
        #expect(appeared)
        // Offline reopen reads the cache, so the message must be stored there.
        let cached = await fixture.cachedMessages()
        #expect(cached.map(\.body) == ["Thinking of you"])
        observing.cancel()
        await observing.value
    }

    @Test func serverCopyOfAStillSendingMessageDoesNotDuplicateIt() async throws {
        let fixture = ChatTestFixture()
        let source = fixture.gateway.liveSource
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        #expect(await waitForMain { source.subscriptionCount.value == 1 })

        #expect(await viewModel.send("On my way"))
        #expect(await waitForMain { viewModel.messages.map(\.isSending) == [true] })

        // The server copy arrives before the send's own response confirms it.
        let serverCopy = fixture.ownServerCopy(body: "On my way", at: 3)
        await fixture.gateway.liveSource.push([serverCopy])
        let settled = await waitForMain { viewModel.messages.map(\.id) == [fixture.messageID] }
        #expect(settled)
        #expect(viewModel.messages.first?.isSending == false)

        // The confirmation that follows keeps a single message.
        let sends = try await fixture.queuedOperations(.sendThreadMessage)
        let operation = try #require(sends.first)
        await fixture.confirm(operation.operation, body: "On my way")
        LocalStoreChanges.post(.dailyChat, ownerUserID: fixture.ownerUserID)
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.messages.map(\.id) == [fixture.messageID])
        observing.cancel()
        await observing.value
    }

    @Test func aStillSendingMessageStaysVisibleWhenOtherMessagesArrive() async {
        let fixture = ChatTestFixture()
        let source = fixture.gateway.liveSource
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        #expect(await waitForMain { source.subscriptionCount.value == 1 })
        _ = await viewModel.send("Not sent yet")

        await fixture.gateway.liveSource.push([fixture.partnerMessage(body: "Hello")])

        let both = await waitForMain { viewModel.messages.map(\.body).sorted() == ["Hello", "Not sent yet"] }
        #expect(both)
        #expect(viewModel.messages.first(where: { $0.body == "Not sent yet" })?.isSending == true)
        observing.cancel()
        await observing.value
    }

    @Test func aThreadThePartnerStartsOpensTheMessageSubscription() async {
        let fixture = ChatTestFixture()
        let source = fixture.gateway.liveSource
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(source.subscriptionCount.value == 0)

        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        LocalStoreChanges.post(.dailyChat, ownerUserID: fixture.ownerUserID)
        #expect(await waitForMain { source.subscriptionCount.value == 1 })

        await fixture.gateway.liveSource.push([fixture.partnerMessage(body: "Hi")])
        #expect(await waitForMain { viewModel.messages.map(\.body) == ["Hi"] })
        observing.cancel()
        await observing.value
    }

    @Test func summaryFeedWritesTheChatCache() async throws {
        let fixture = ChatTestFixture()
        let cache = fixture.cache
        let transport = ChatPushTransport()
        let session = SyncSession(userID: fixture.ownerUserID, activeCoupleID: fixture.question.coupleID)
        let feed = DailyQuestionChatLiveFeed(cache: cache)
        let task = Task { await feed.run(session: session, live: LiveQueryService(transport: transport)) }

        await transport.push(
            """
            [{"thread_id":"\(fixture.threadID.uuidString)","couple_id":"\(fixture.question.coupleID.uuidString)",
            "kind":"daily_question","daily_question_id":"\(fixture.question.questionID.uuidString)",
            "created_at":"2026-05-01T10:00:00.000Z","updated_at":"2026-05-01T10:00:05.000Z","deleted_at":null,
            "moderation_status":"visible","last_message_id":"\(fixture.messageID.uuidString)",
            "last_message_at":"2026-05-01T10:00:05.000Z",
            "last_message_sender_user_id":"\(fixture.partnerUserID.uuidString)",
            "last_message_deleted_at":null,"last_message_moderation_status":"visible","last_message_body":"Miss you"}]
            """
        )

        let owner = fixture.ownerUserID
        let stored = await waitUntil { await cache.summaries(ownerUserID: owner).count == 1 }
        #expect(stored)
        let summaries = await cache.summaries(ownerUserID: owner)
        #expect(summaries.first?.lastMessageBody == "Miss you")
        #expect(summaries.first?.threadID == fixture.threadID)
        #expect(transport.openedPaths.value == ["threads:get_conversation_threads"])
        task.cancel()
        await task.value
    }

    @Test func aSecondLiveResultBeforeTheSendResponseDoesNotShowTheMessageTwice() async throws {
        let fixture = ChatTestFixture()
        let source = fixture.gateway.liveSource
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        #expect(await waitForMain { source.subscriptionCount.value == 1 })
        #expect(await viewModel.send("On my way"))

        let serverCopy = fixture.ownServerCopy(body: "On my way", at: 3)
        await source.push([serverCopy])
        #expect(await waitForMain { viewModel.messages.map(\.id) == [fixture.messageID] })

        // The next live result arrives before the send's own response. It carries the
        // same server copy, still without an operation id.
        await source.push([serverCopy, fixture.partnerMessage(body: "Hello", at: 6)])
        #expect(await waitForMain { viewModel.messages.count >= 2 })
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.messages.map(\.body) == ["On my way", "Hello"])
        let isStillSending = viewModel.messages.contains(where: \.isSending)
        #expect(!isStillSending)
        observing.cancel()
        await observing.value
    }
}
