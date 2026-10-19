import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatViewModelTests {
    @Test func aSeenAnswerThatFailedToSendIsSentAgainUntilTheServerHasIt() async {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await fixture.gateway.setAnswerSeenFailure(true)
        await viewModel.load()

        // Coming back to the page tries again after a failure.
        for _ in 0..<200 where await fixture.gateway.answerSeenCallCount < 2 {
            viewModel.setScreenActive(false)
            viewModel.setScreenActive(true)
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await fixture.gateway.answerSeenCallCount >= 2)

        // Once the server has it, the page stops sending.
        await fixture.gateway.setAnswerSeenFailure(false)
        let callsBeforeSuccess = await fixture.gateway.answerSeenCallCount
        for _ in 0..<200 where await fixture.gateway.answerSeenCallCount == callsBeforeSuccess {
            viewModel.setScreenActive(false)
            viewModel.setScreenActive(true)
            try? await Task.sleep(for: .milliseconds(5))
        }
        let callsAfterSuccess = await fixture.gateway.answerSeenCallCount
        for _ in 0..<5 {
            viewModel.setScreenActive(false)
            viewModel.setScreenActive(true)
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await fixture.gateway.answerSeenCallCount == callsAfterSuccess)
    }

    @Test func firstSendQueuesLazyThreadCreationAndOptimisticMessage() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()
        #expect(await fixture.gateway.createCallCount == 0)

        let sent = await viewModel.send("  I liked your answer.  ")
        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)

        #expect(sent)
        #expect(creates.count == 1)
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.body == "I liked your answer.")
        #expect(viewModel.messages.first?.isSending == true)
    }

    @Test func laterOfflineSendsQueueSendOperationsWithoutCreatingAnotherThread() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        _ = await viewModel.send("First")
        _ = await viewModel.send("Second")

        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        let sends = try await fixture.queuedOperations(.sendThreadMessage)
        #expect(creates.count == 1)
        #expect(sends.count == 1)
        let payload = try #require(sends.first?.requestData)
        let decoded = try JSONDecoder().decode(
            SendDailyChatMessagePayload.self,
            from: payload
        )
        #expect(decoded.threadID == nil)
    }

    @Test func confirmedOptimisticMessageReconcilesWithoutDuplication() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        _ = await viewModel.send("One message")

        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        let operation = try #require(creates.first)
        await fixture.cache.confirm(
            ownerUserID: fixture.ownerUserID,
            questionID: fixture.question.questionID,
            coupleID: fixture.question.coupleID,
            clientOperationID: operation.operation.id,
            threadID: fixture.threadID,
            messageID: fixture.messageID,
            body: "One message",
            senderUserID: fixture.ownerUserID,
            createdAt: operation.operation.localCreatedAt
        )
        try await fixture.pendingStore.markSucceeded(
            clientOperationID: operation.operation.id,
            at: .now
        )
        await fixture.gateway.setRemote(
            summaries: [fixture.summary],
            messages: [fixture.remoteMessage(body: "One message")]
        )

        await viewModel.load()

        #expect(viewModel.messages.map(\.id) == [fixture.messageID])
        #expect(viewModel.messages.first?.isSending == false)
    }

    @Test func failedCachedSendStaysVisibleWithoutRaisingABannerOnOpen() async {
        let fixture = ChatTestFixture()
        _ = await fixture.cacheFailedMessage("Keep this message")
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        // The red icon on the message is enough. A banner on every visit would nag.
        #expect(viewModel.notice == nil)
        #expect(viewModel.messages.first?.body == "Keep this message")
        #expect(viewModel.messages.first?.sendFailed == true)
    }

    @Test func aRejectedFirstMessageDoesNotBlockTheRetryFromCreatingTheThread() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        #expect(await viewModel.send("Hello"))
        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        let operation = try #require(creates.first)
        await fixture.cache.markFailed(
            ownerUserID: fixture.ownerUserID,
            clientOperationID: operation.operation.id
        )
        LocalStoreChanges.post(.dailyChat, ownerUserID: fixture.ownerUserID)
        #expect(await waitForMain { viewModel.messages.first?.sendFailed == true })

        #expect(await viewModel.send("Hello", replacingFailed: operation.operation.id))

        // The retry starts the thread again. It is not a message for a thread that never existed.
        let recreates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        #expect(recreates.count == 2)
        observing.cancel()
        await observing.value
    }

    @Test func doubleTapSendsOnceAndQueuesOneThreadCreation() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        async let first = viewModel.send("On my way")
        async let second = viewModel.send("On my way")
        let (didSendFirst, didSendSecond) = await (first, second)

        #expect([didSendFirst, didSendSecond].filter { $0 }.count == 1)
        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        let sends = try await fixture.queuedOperations(.sendThreadMessage)
        #expect(creates.count == 1)
        #expect(sends.isEmpty)
        #expect(viewModel.messages.count == 1)
    }

    @Test func retryingAFailedMessageReplacesItInsteadOfAddingACopy() async throws {
        let fixture = ChatTestFixture()
        let operation = await fixture.cacheFailedMessage("Keep this message")
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        #expect(viewModel.messages.map(\.sendFailed) == [true])

        let sent = await viewModel.send("Keep this message", replacingFailed: operation.id)

        #expect(sent)
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.sendFailed == false)
        #expect(viewModel.messages.first?.isSending == true)
        let cached = await fixture.cachedMessages()
        #expect(cached.count == 1)
        #expect(cached.first?.sendFailed == false)
    }

    @Test func messageLimitCountsCodePointsLikeTheServer() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        // One family emoji is a single character but five code points.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

        #expect(await viewModel.send(String(repeating: family, count: 801)) == false)
        #expect(viewModel.notice == .messageTooLong)
        let creates = try await fixture.queuedOperations(.createDailyQuestionThreadWithMessage)
        #expect(creates.isEmpty)

        // 800 of them are exactly 4,000 code points.
        #expect(await viewModel.send(String(repeating: family, count: 800)))
    }
}
