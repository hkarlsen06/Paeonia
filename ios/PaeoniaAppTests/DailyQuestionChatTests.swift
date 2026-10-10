import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct DailyQuestionChatViewModelTests {
    @Test func firstSendQueuesLazyThreadCreationAndOptimisticMessage() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()
        #expect(await fixture.gateway.createCallCount == 0)

        let sent = await viewModel.send("  I liked your answer.  ")
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )

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

        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        let sends = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .sendThreadMessage
        )
        #expect(creates.count == 1)
        #expect(sends.count == 1)
        let payload = try #require(sends.first?.requestData)
        let decoded = try JSONDecoder().decode(
            SendDailyQuestionThreadMessageOperationPayload.self,
            from: payload
        )
        #expect(decoded.threadID == nil)
    }

    @Test func confirmedOptimisticMessageReconcilesWithoutDuplication() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()
        _ = await viewModel.send("One message")

        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        let operation = try #require(creates.first)
        await fixture.cache.confirm(
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id,
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

    @Test func whitespaceMessageIsRejected() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        #expect(await viewModel.send(" \n\t ") == false)
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        #expect(creates.isEmpty)
    }

    @Test func oversizedMessageIsRejectedWithoutQueueing() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await viewModel.load()

        #expect(await viewModel.send(String(repeating: "a", count: 4_001)) == false)
        #expect(viewModel.notice == .messageTooLong)
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        #expect(creates.isEmpty)
    }

    @Test func failedCachedSendSurfacesHumanErrorWithoutDroppingMessage() async {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: nil,
                instanceID: fixture.question.id,
                senderUserID: fixture.ownerUserID,
                body: "Keep this message",
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: fixture.ownerUserID
        )
        await fixture.cache.markFailed(
            ownerUserID: fixture.ownerUserID,
            clientOperationID: operation.id
        )
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        #expect(viewModel.notice == .sendFailed)
        #expect(viewModel.messages.first?.body == "Keep this message")
        #expect(viewModel.messages.first?.sendFailed == true)
    }

    @Test func chatRejectsSendUntilPartnerAnswerIsRevealed() async throws {
        let fixture = ChatTestFixture(question: makeChatQuestion(revealed: false))
        let viewModel = fixture.makeViewModel()

        #expect(viewModel.isChatAvailable == false)
        #expect(await viewModel.send("Hello") == false)
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        #expect(creates.isEmpty)
    }

    @Test func openingChatNeverCreatesAnEmptyThread() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        #expect(await fixture.gateway.createCallCount == 0)
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        #expect(creates.isEmpty)
    }
}

struct DailyQuestionChatMergeTests {
    @Test func mergeOrdersMessagesAndKeepsOneCopyPerOperation() throws {
        let instanceID = UUID()
        let senderID = UUID()
        let operationID = UUID()
        let first = DailyQuestionChatMessage(
            id: UUID(),
            threadID: UUID(),
            instanceID: instanceID,
            senderUserID: senderID,
            body: "First",
            createdAt: Date(timeIntervalSince1970: 1),
            clientOperationID: nil,
            isSending: false
        )
        let confirmed = DailyQuestionChatMessage(
            id: UUID(),
            threadID: UUID(),
            instanceID: instanceID,
            senderUserID: senderID,
            body: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            clientOperationID: operationID,
            isSending: false
        )
        let optimistic = DailyQuestionChatMessage(
            id: operationID,
            threadID: nil,
            instanceID: instanceID,
            senderUserID: senderID,
            body: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            clientOperationID: operationID,
            isSending: true
        )

        let merged = DailyQuestionChatMessage.visibleOrdered(
            remote: [confirmed, first],
            optimistic: [optimistic]
        )

        #expect(merged.map(\.body) == ["First", "Second"])
    }
}

@MainActor
struct DailyQuestionChatPendingOperationHandlerTests {
    @Test func createHandlerConfirmsMessageByClientOperationID() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        let optimistic = DailyQuestionChatMessage(
            id: operation.id,
            threadID: nil,
            instanceID: fixture.question.id,
            senderUserID: fixture.ownerUserID,
            body: "Hello",
            createdAt: operation.localCreatedAt,
            clientOperationID: operation.id,
            isSending: true
        )
        await fixture.cache.append(optimistic, ownerUserID: fixture.ownerUserID)
        let payload = CreateDailyQuestionThreadMessageOperationPayload(
            instanceID: fixture.question.id,
            coupleID: fixture.question.coupleID,
            body: "Hello"
        )
        let snapshot = pendingSnapshot(
            ownerUserID: fixture.ownerUserID,
            operation: operation,
            kind: .createDailyQuestionThreadWithMessage,
            payload: try JSONEncoder().encode(payload)
        )
        let handler = CreateDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        )

        let result = try await handler.send(snapshot, context: chatSyncContext(ownerUserID: fixture.ownerUserID))
        let messages = await fixture.cache.messages(
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )

        #expect(result == .succeeded)
        #expect(messages.first?.id == fixture.messageID)
        #expect(messages.first?.clientOperationID == operation.id)
        #expect(messages.first?.isSending == false)
    }

    @Test func sendHandlerResolvesThreadCreatedByEarlierQueuedOperation() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: nil,
                instanceID: fixture.question.id,
                senderUserID: fixture.ownerUserID,
                body: "Second",
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: fixture.ownerUserID
        )
        let payload = SendDailyQuestionThreadMessageOperationPayload(
            instanceID: fixture.question.id,
            coupleID: fixture.question.coupleID,
            threadID: nil,
            body: "Second"
        )
        let handler = SendDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        )

        let result = try await handler.send(
            pendingSnapshot(
                ownerUserID: fixture.ownerUserID,
                operation: operation,
                kind: .sendThreadMessage,
                payload: try JSONEncoder().encode(payload)
            ),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )

        #expect(result == .succeeded)
        #expect(await fixture.gateway.sendCallCount == 1)
    }

    @Test func thrownHandlerFailureRemainsRetryableInDrain() async throws {
        let fixture = ChatTestFixture()
        await fixture.gateway.setFailure(true)
        let operation = fixture.operationProvider.makeOperation()
        let payload = CreateDailyQuestionThreadMessageOperationPayload(
            instanceID: fixture.question.id,
            coupleID: fixture.question.coupleID,
            body: "Hello"
        )
        try await fixture.pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: fixture.ownerUserID,
                operation: operation,
                operationKind: .createDailyQuestionThreadWithMessage,
                idempotencyScope: "chat",
                requestData: try JSONEncoder().encode(payload)
            )
        )
        let handler = CreateDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        )
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        try await stream.push(context: chatSyncContext(
            ownerUserID: fixture.ownerUserID,
            pendingStore: fixture.pendingStore
        ))

        let pending = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        #expect(pending.first?.status == .failedRetryable)
    }
}

@MainActor
private func waitForMain(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
struct DailyQuestionChatLiveTests {
    private func partnerMessage(_ fixture: ChatTestFixture, body: String, id: UUID = UUID(), at seconds: Double = 5) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: id,
            threadID: fixture.threadID,
            instanceID: fixture.question.id,
            senderUserID: fixture.partnerUserID,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds),
            clientOperationID: nil,
            isSending: false
        )
    }

    @Test func partnerMessageAppearsWhileTheChatIsOpenAndIsCached() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }

        await fixture.gateway.liveSource.push([partnerMessage(fixture, body: "Thinking of you")])

        let appeared = await waitForMain { viewModel.messages.map(\.body) == ["Thinking of you"] }
        #expect(appeared)
        // Offline reopen reads the cache, so the message must be stored there.
        let cached = await fixture.cache.messages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id)
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
        #expect(viewModel.messages.map(\.isSending) == [true])

        // The server copy arrives before the send's own response confirms it.
        let serverCopy = DailyQuestionChatMessage(
            id: fixture.messageID,
            threadID: fixture.threadID,
            instanceID: fixture.question.id,
            senderUserID: fixture.ownerUserID,
            body: "On my way",
            createdAt: Date(timeIntervalSince1970: 3),
            clientOperationID: nil,
            isSending: false
        )
        await fixture.gateway.liveSource.push([serverCopy])
        let settled = await waitForMain { viewModel.messages.map(\.id) == [fixture.messageID] }
        #expect(settled)
        #expect(viewModel.messages.first?.isSending == false)

        // The confirmation that follows keeps a single message.
        let sends = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .sendThreadMessage
        )
        let operation = try #require(sends.first)
        await fixture.cache.confirm(
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id,
            coupleID: fixture.question.coupleID,
            clientOperationID: operation.operation.id,
            threadID: fixture.threadID,
            messageID: fixture.messageID,
            body: "On my way",
            senderUserID: fixture.ownerUserID,
            createdAt: operation.operation.localCreatedAt
        )
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

        await fixture.gateway.liveSource.push([partnerMessage(fixture, body: "Hello")])

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

        await fixture.gateway.liveSource.push([partnerMessage(fixture, body: "Hi")])
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
            "kind":"daily_question","daily_question_instance_id":"\(fixture.question.id.uuidString)",
            "created_at":"2026-05-01T10:00:00.000Z","updated_at":"2026-05-01T10:00:05.000Z","deleted_at":null,
            "moderation_status":"visible","last_message_id":"\(fixture.messageID.uuidString)",
            "last_message_at":"2026-05-01T10:00:05.000Z","last_message_sender_user_id":"\(fixture.partnerUserID.uuidString)",
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

        let serverCopy = DailyQuestionChatMessage(
            id: fixture.messageID,
            threadID: fixture.threadID,
            instanceID: fixture.question.id,
            senderUserID: fixture.ownerUserID,
            body: "On my way",
            createdAt: Date(timeIntervalSince1970: 3),
            clientOperationID: nil,
            isSending: false
        )
        await source.push([serverCopy])
        #expect(await waitForMain { viewModel.messages.map(\.id) == [fixture.messageID] })

        // The next live result arrives before the send's own response. It carries the
        // same server copy, still without an operation id.
        await source.push([serverCopy, partnerMessage(fixture, body: "Hello", at: 6)])
        #expect(await waitForMain { viewModel.messages.count >= 2 })
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.messages.map(\.body) == ["On my way", "Hello"])
        #expect(!viewModel.hasSendingMessages)
        observing.cancel()
        await observing.value
    }

    @Test func claimingPendingKeepsTheOperationOfAMessageTheCacheAlreadyClaimed() {
        let owner = UUID()
        let instance = UUID()
        let serverID = UUID()
        let operation = UUID()
        func message(_ id: UUID, operation: UUID? = nil, sending: Bool = false) -> DailyQuestionChatMessage {
            DailyQuestionChatMessage(
                id: id, threadID: nil, instanceID: instance, senderUserID: owner, body: "ok",
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
            instanceID: fixture.question.id,
            threadID: fixture.threadID
        )
        var iterator = updates.makeAsyncIterator()

        await fixture.gateway.liveSource.push([partnerMessage(fixture, body: "Before")])
        await iterator.next()
        #expect(await fixture.cache.messages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id).count == 1)

        // Sign-out clears the cache. The subscription can still deliver one more result.
        await fixture.cache.clearAll()
        await fixture.gateway.liveSource.push([partnerMessage(fixture, body: "After")])

        #expect(await iterator.next() == nil)
        #expect(await fixture.cache.messages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id).isEmpty)
    }

    @Test func theFileCacheRefusesAMessageSaveThatStartedBeforeAPurge() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatCachePurge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let fixture = ChatTestFixture()
        let message = partnerMessage(fixture, body: "Private")

        let started = await cache.purgeGeneration()
        await cache.clearAll()
        let wrote = await cache.saveMessages(
            [message],
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id,
            unlessPurgedSince: started
        )

        #expect(!wrote)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let current = await cache.purgeGeneration()
        #expect(await cache.saveMessages(
            [message],
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id,
            unlessPurgedSince: current
        ))
        #expect(await cache.messages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id).count == 1)
    }

    @Test func claimingPendingMatchesTheOldestSendingMessageOnce() {
        let owner = UUID()
        let instance = UUID()
        func message(_ id: UUID, _ body: String, at seconds: Double, operation: UUID? = nil, sending: Bool = false) -> DailyQuestionChatMessage {
            DailyQuestionChatMessage(
                id: id, threadID: nil, instanceID: instance, senderUserID: owner, body: body,
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
}

private final class ChatPushTransport: LiveQueryTransport, @unchecked Sendable {
    private let open = LockedBox<AsyncThrowingStream<Data, any Error>.Continuation?>(nil)
    let openedPaths = LockedBox<[String]>([])

    func updates(path: String, args _: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        openedPaths.mutate { $0.append(path) }
        return AsyncThrowingStream { continuation in
            open.mutate { $0 = continuation }
        }
    }

    func push(_ json: String) async {
        _ = await waitUntil { open.value != nil }
        open.value?.yield(Data(json.utf8))
    }
}

@MainActor
private final class ChatTestOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    let clientID = UUID()

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

@MainActor
private final class ChatTestFixture {
    let ownerUserID: UUID
    let partnerUserID: UUID
    let threadID = UUID()
    let messageID = UUID()
    let question: DailyChallengeQuestion
    let gateway: ChatTestGateway
    let cache = InMemoryDailyQuestionChatCache()
    let pendingStore = InMemoryPendingSyncOperationRepository()
    let operationProvider = ChatTestOperationProvider()

    init(question: DailyChallengeQuestion? = nil) {
        ownerUserID = question?.ownAnswerDetail?.answerUserID ?? UUID()
        partnerUserID = question?.partnerAnswerDetail?.answerUserID ?? UUID()
        self.question = question ?? makeChatQuestion(
            ownerUserID: ownerUserID,
            partnerUserID: partnerUserID
        )
        gateway = ChatTestGateway(threadID: threadID, messageID: messageID)
    }

    var summary: DailyQuestionThreadSummary {
        DailyQuestionThreadSummary(
            threadID: threadID,
            coupleID: question.coupleID,
            instanceID: question.id,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            lastMessageID: messageID,
            lastMessageAt: Date(timeIntervalSince1970: 2),
            lastMessageSenderUserID: ownerUserID,
            lastMessageBody: "One message"
        )
    }

    func remoteMessage(body: String) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            instanceID: question.id,
            senderUserID: ownerUserID,
            body: body,
            createdAt: Date(timeIntervalSince1970: 2),
            clientOperationID: nil,
            isSending: false
        )
    }

    func makeViewModel() -> DailyQuestionChatViewModel {
        DailyQuestionChatViewModel(
            question: question,
            participants: DailyChallengeParticipants(
                currentUserID: ownerUserID,
                currentDisplayName: "You",
                partnerUserID: partnerUserID,
                partnerDisplayName: "Partner"
            ),
            service: DailyQuestionChatService(
                gateway: gateway,
                cache: cache,
                pendingOperationStore: pendingStore
            ),
            operationProvider: operationProvider
        )
    }
}

/// Stands in for the messages subscription. Tests push the full message list, like
/// the server pushing a new query result.
private final class LiveMessageSource: @unchecked Sendable {
    private let open = LockedBox<AsyncStream<[DailyQuestionChatMessage]>.Continuation?>(nil)
    let subscriptionCount = LockedBox(0)

    func stream() -> AsyncStream<[DailyQuestionChatMessage]> {
        subscriptionCount.mutate { $0 += 1 }
        return AsyncStream { continuation in
            open.mutate { $0 = continuation }
        }
    }

    func push(_ messages: [DailyQuestionChatMessage]) async {
        _ = await waitUntil { open.value != nil }
        open.value?.yield(messages)
    }
}

private actor ChatTestGateway: DailyQuestionChatGateway {
    nonisolated let liveSource = LiveMessageSource()
    private let threadID: UUID
    private let messageID: UUID
    private var summaries: [DailyQuestionThreadSummary] = []
    private var messages: [DailyQuestionChatMessage] = []
    private var shouldFail = false
    private(set) var createCallCount = 0
    private(set) var sendCallCount = 0

    init(threadID: UUID, messageID: UUID) {
        self.threadID = threadID
        self.messageID = messageID
    }

    func setRemote(
        summaries: [DailyQuestionThreadSummary],
        messages: [DailyQuestionChatMessage]
    ) {
        self.summaries = summaries
        self.messages = messages
    }

    func setFailure(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func loadThreadSummaries() throws -> [DailyQuestionThreadSummary] {
        if shouldFail { throw ChatTestError.requested }
        return summaries
    }

    func loadMessages(threadID _: UUID, instanceID _: UUID) throws -> [DailyQuestionChatMessage] {
        if shouldFail { throw ChatTestError.requested }
        return messages
    }

    nonisolated func liveMessages(threadID _: UUID, instanceID _: UUID) -> AsyncStream<[DailyQuestionChatMessage]> {
        liveSource.stream()
    }

    func createThreadWithMessage(
        _: CreateDailyQuestionThreadMessageOperationPayload,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse {
        createCallCount += 1
        if shouldFail { throw ChatTestError.requested }
        return DailyQuestionThreadMessageResponse(threadID: threadID, messageID: messageID)
    }

    func sendMessage(
        threadID _: UUID,
        body _: String,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse {
        sendCallCount += 1
        if shouldFail { throw ChatTestError.requested }
        return DailyQuestionThreadMessageResponse(threadID: threadID, messageID: messageID)
    }
}

private actor InMemoryDailyQuestionChatCache: DailyQuestionChatCaching {
    private var storedSummaries: [UUID: [DailyQuestionThreadSummary]] = [:]
    private var storedMessages: [UUID: [UUID: [DailyQuestionChatMessage]]] = [:]
    private var generation = 0

    func summaries(ownerUserID: UUID) -> [DailyQuestionThreadSummary] {
        storedSummaries[ownerUserID] ?? []
    }

    func messages(ownerUserID: UUID, instanceID: UUID) -> [DailyQuestionChatMessage] {
        storedMessages[ownerUserID]?[instanceID] ?? []
    }

    func saveSummaries(_ summaries: [DailyQuestionThreadSummary], ownerUserID: UUID) {
        storedSummaries[ownerUserID] = summaries
    }

    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID
    ) {
        let optimistic = storedMessages[ownerUserID]?[instanceID] ?? []
        storedMessages[ownerUserID, default: [:]][instanceID] = DailyQuestionChatMessage.visibleOrdered(
            remote: messages,
            optimistic: optimistic
        )
    }

    func append(_ message: DailyQuestionChatMessage, ownerUserID: UUID) {
        storedMessages[ownerUserID, default: [:]][message.instanceID, default: []].append(message)
    }

    func markFailed(ownerUserID: UUID, clientOperationID: UUID) {
        guard let instanceIDs = storedMessages[ownerUserID]?.keys else { return }
        for instanceID in instanceIDs {
            guard let index = storedMessages[ownerUserID]?[instanceID]?.firstIndex(where: {
                $0.clientOperationID == clientOperationID
            }) else { continue }
            var message = storedMessages[ownerUserID]![instanceID]![index]
            message.sendFailed = true
            storedMessages[ownerUserID]![instanceID]![index] = message
            return
        }
    }

    func confirm(
        ownerUserID: UUID,
        instanceID: UUID,
        coupleID: UUID,
        clientOperationID: UUID,
        threadID: UUID,
        messageID: UUID,
        body: String,
        senderUserID: UUID,
        createdAt: Date
    ) {
        let index = storedMessages[ownerUserID]?[instanceID]?.firstIndex(where: {
            $0.clientOperationID == clientOperationID
        })
        let confirmed = DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: clientOperationID,
            isSending: false
        )
        if let index {
            storedMessages[ownerUserID]![instanceID]![index] = confirmed
        } else {
            storedMessages[ownerUserID, default: [:]][instanceID, default: []].append(confirmed)
        }
        if storedSummaries[ownerUserID]?.contains(where: { $0.instanceID == instanceID }) != true {
            storedSummaries[ownerUserID, default: []].append(
                DailyQuestionThreadSummary(
                    threadID: threadID,
                    coupleID: coupleID,
                    instanceID: instanceID,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    lastMessageID: messageID,
                    lastMessageAt: createdAt,
                    lastMessageSenderUserID: senderUserID,
                    lastMessageBody: body
                )
            )
        }
    }

    func clearAll() {
        generation += 1
        storedSummaries = [:]
        storedMessages = [:]
    }

    func purgeGeneration() -> Int {
        generation
    }

    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveMessages(messages, ownerUserID: ownerUserID, instanceID: instanceID)
        return true
    }
}

private enum ChatTestError: Error {
    case requested
}

private func pendingSnapshot(
    ownerUserID: UUID,
    operation: SyncClientOperation,
    kind: SyncPendingOperationKind,
    payload: Data
) -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: ownerUserID,
        operation: operation,
        operationKind: kind,
        idempotencyScope: "chat",
        requestHash: nil,
        requestData: payload,
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}

private func chatSyncContext(
    ownerUserID: UUID,
    pendingStore: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository()
) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: ownerUserID),
        reason: .localChange,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: pendingStore
    )
}

private func makeChatQuestion(
    ownerUserID: UUID = UUID(),
    partnerUserID: UUID = UUID(),
    revealed: Bool = true
) -> DailyChallengeQuestion {
    let ownAnswerID = UUID()
    let partnerAnswerID = UUID()
    return DailyChallengeQuestion(
        id: UUID(),
        coupleDayID: UUID(),
        coupleID: UUID(),
        localDate: "2026-08-04",
        effectiveLocalDate: "2026-08-04",
        startsAt: Date(timeIntervalSince1970: 1),
        endsAt: Date(timeIntervalSince1970: 2),
        seededForUserID: ownerUserID,
        slotNumber: 1,
        status: .answered,
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "chat.test",
        prompt: "What made you smile today?",
        shortPrompt: "A smile today",
        answerKinds: [.text],
        ownAnswer: DailyQuestionAnswerSummary(id: ownAnswerID, answeredAt: .now),
        partnerAnswer: DailyQuestionAnswerSummary(id: partnerAnswerID, answeredAt: .now),
        canViewPartnerAnswer: revealed,
        ownAnswerDetail: DailyQuestionAnswerDetail(
            answerUserID: ownerUserID,
            answerID: ownAnswerID,
            answeredAt: .now,
            isOwnAnswer: true,
            canViewAnswer: true,
            textBody: "A good morning.",
            selectedUserID: nil,
            mediaAssetIDs: []
        ),
        partnerAnswerDetail: DailyQuestionAnswerDetail(
            answerUserID: partnerUserID,
            answerID: partnerAnswerID,
            answeredAt: .now,
            isOwnAnswer: false,
            canViewAnswer: revealed,
            textBody: revealed ? "Your message." : nil,
            selectedUserID: nil,
            mediaAssetIDs: []
        ),
        origin: .own,
        isCurrentDay: true
    )
}
