import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ThreadChatOperationHandlerTests {
    @Test func createHandlerConfirmsMessageByClientOperationID() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.appendSending(operation, body: "Hello")

        let result = try await fixture.createHandler().send(
            try fixture.createSnapshot(operation, body: "Hello"),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )
        let messages = await fixture.cachedMessages()

        #expect(result == .succeeded)
        #expect(messages.first?.id == fixture.messageID)
        #expect(messages.first?.clientOperationID == operation.id)
        #expect(messages.first?.isSending == false)
    }

    @Test func sendHandlerResolvesThreadCreatedByEarlierQueuedOperation() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.appendSending(operation, body: "Second")

        let result = try await fixture.sendHandler().send(
            try fixture.sendSnapshot(operation, body: "Second", threadID: nil),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )

        #expect(result == .succeeded)
        #expect(await fixture.gateway.sendCallCount == 1)
    }

    @Test func thrownHandlerFailureRemainsRetryableInDrain() async throws {
        let fixture = ChatTestFixture()
        await fixture.gateway.setFailure(true)
        let operation = fixture.operationProvider.makeOperation()
        try await fixture.pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: fixture.ownerUserID,
                operation: operation,
                operationKind: .createChatThreadWithMessage,
                idempotencyScope: "chat",
                requestData: try JSONEncoder().encode(fixture.createPayload(body: "Hello"))
            )
        )
        let stream = PendingSyncOperationDrainStream(
            handlers: [fixture.createHandler()],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        try await stream.push(context: chatSyncContext(
            ownerUserID: fixture.ownerUserID,
            pendingStore: fixture.pendingStore
        ))

        let pending = try await fixture.queuedOperations(.createChatThreadWithMessage)
        #expect(pending.first?.status == .failedRetryable)
    }
}

@MainActor
struct ThreadChatOperationFailureTests {
    @Test func sendHandlerMarksAServerRejectionAsFailedAndStopsRetrying() async throws {
        let fixture = ChatTestFixture()
        let recorder = ChatChangeRecorder(ownerUserID: fixture.ownerUserID)
        defer { recorder.stop() }
        let operation = fixture.operationProvider.makeOperation()
        await fixture.appendSending(operation, body: "Second", threadID: fixture.threadID)
        await fixture.gateway.setSendError(
            PaeoniaConvexError.server(code: "23514", message: "thread message body is too long")
        )

        let result = try await fixture.sendHandler().send(
            try fixture.sendSnapshot(operation, body: "Second", threadID: fixture.threadID),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )

        var isTerminal = false
        if case .terminalFailure = result { isTerminal = true }
        #expect(isTerminal)
        let cached = await fixture.cachedMessages()
        #expect(cached.first?.sendFailed == true)
        #expect(cached.first?.isSending == false)
        let changes = recorder.count
        #expect(await waitUntil { changes.value == 1 })
    }

    @Test func aMessageTheDrainGivesUpOnShowsAsFailedInTheChat() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.appendSending(operation, body: "Second", threadID: fixture.threadID)

        await fixture.sendHandler().gaveUp(
            on: try fixture.sendSnapshot(operation, body: "Second", threadID: fixture.threadID),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )

        let cached = await fixture.cachedMessages()
        #expect(cached.first?.sendFailed == true)
        #expect(cached.first?.isSending == false)
    }

    @Test func sendHandlerKeepsAConnectionErrorRetryable() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.gateway.setSendError(URLError(.notConnectedToInternet))
        let handler = fixture.sendHandler()

        var threw = false
        do {
            _ = try await handler.send(
                try fixture.sendSnapshot(operation, body: "Second", threadID: fixture.threadID),
                context: chatSyncContext(ownerUserID: fixture.ownerUserID)
            )
        } catch {
            threw = true
        }

        #expect(threw)
    }

    /// A message written in one couple must not be sent to the couple the user joined later.
    @Test func aMessageFromAnEarlierRelationshipIsNotSentToTheNewOne() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.appendSending(operation, body: "Hi")
        let context = SyncContext(
            session: SyncSession(userID: fixture.ownerUserID, activeCoupleID: UUID()),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: fixture.pendingStore
        )

        let result = try await fixture.createHandler().send(
            try fixture.createSnapshot(operation, body: "Hi"),
            context: context
        )

        var isTerminal = false
        if case .terminalFailure = result { isTerminal = true }
        #expect(isTerminal)
        #expect(await fixture.gateway.createCallCount == 0)
        #expect(await fixture.cachedMessages().first?.sendFailed == true)
    }

    private func enqueueCreate(_ fixture: ChatTestFixture, operation: SyncClientOperation, data: Data) async throws {
        try await fixture.pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: fixture.ownerUserID,
                operation: operation,
                operationKind: .createChatThreadWithMessage,
                idempotencyScope: "chat",
                requestData: data
            )
        )
    }

    /// Queues a send with no thread yet, like a message typed before the chat's first message went out.
    private func enqueueThreadlessSend(
        _ fixture: ChatTestFixture,
        operation: SyncClientOperation,
        subjectID: UUID,
        body: String
    ) async throws {
        try await fixture.pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: fixture.ownerUserID,
                operation: operation,
                operationKind: .sendThreadMessage,
                idempotencyScope: "chat",
                requestData: try JSONEncoder().encode(
                    fixture.sendPayload(body: body, threadID: nil, subjectID: subjectID)
                )
            )
        )
    }

    /// A message queued behind a refused thread used to retry forever.
    @Test func aRefusedThreadFailsTheMessagesWaitingForIt() async throws {
        let fixture = ChatTestFixture()
        let ownerUserID = fixture.ownerUserID
        let subjectID = fixture.question.questionID
        let otherQuestionID = UUID()
        let create = fixture.operationProvider.makeOperation()
        let waiting = fixture.operationProvider.makeOperation()
        let otherChat = fixture.operationProvider.makeOperation()
        let createData = try JSONEncoder().encode(fixture.createPayload(body: "First"))

        await fixture.appendSending(create, body: "First")
        await fixture.appendSending(waiting, body: "Second")
        await fixture.appendSending(otherChat, body: "Other chat", subjectID: otherQuestionID)
        try await enqueueCreate(fixture, operation: create, data: createData)
        // Both sends have no thread id yet. Only the one for the refused chat may fail.
        try await enqueueThreadlessSend(fixture, operation: waiting, subjectID: subjectID, body: "Second")
        try await enqueueThreadlessSend(fixture, operation: otherChat, subjectID: otherQuestionID, body: "Other chat")
        await fixture.gateway.setSendError(
            PaeoniaConvexError.server(code: "P0001", message: "you must answer this daily question")
        )

        let result = try await fixture.createHandler().send(
            chatPendingSnapshot(
                ownerUserID: ownerUserID,
                operation: create,
                kind: .createChatThreadWithMessage,
                payload: createData
            ),
            context: chatSyncContext(ownerUserID: ownerUserID, pendingStore: fixture.pendingStore)
        )

        var isTerminal = false
        if case .terminalFailure = result { isTerminal = true }
        #expect(isTerminal)
        let stillWaiting = try await fixture.queuedOperations(.sendThreadMessage)
        #expect(stillWaiting.map(\.operation.id) == [otherChat.id])
        let refusedChat = await fixture.cachedMessages()
        #expect(refusedChat.first(where: { $0.clientOperationID == waiting.id })?.sendFailed == true)
        let untouchedChat = await fixture.cache.messages(ownerUserID: ownerUserID, subjectID: otherQuestionID)
        #expect(untouchedChat.first?.sendFailed == false)
        #expect(untouchedChat.first?.isSending == true)
    }
}
