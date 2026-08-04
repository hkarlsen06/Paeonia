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

private actor ChatTestGateway: SupabaseDailyQuestionChatGateway {
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
        storedSummaries = [:]
        storedMessages = [:]
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
