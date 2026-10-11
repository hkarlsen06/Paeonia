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

    @Test func aMessageTheServerRejectsWhileTheChatIsOpenRaisesOneBanner() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        #expect(await viewModel.send("Hello"))
        #expect(await waitForMain { viewModel.messages.map(\.isSending) == [true] })
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        let operation = try #require(creates.first)

        // The handler marks the message failed, then tells the open chat.
        await fixture.cache.markFailed(
            ownerUserID: fixture.ownerUserID,
            clientOperationID: operation.operation.id
        )
        LocalStoreChanges.post(.dailyChat, ownerUserID: fixture.ownerUserID)
        #expect(await waitForMain { viewModel.notice == .deliveryFailed })

        // The same failure does not raise the banner again on the next change.
        viewModel.dismissNotice()
        LocalStoreChanges.post(.dailyChat, ownerUserID: fixture.ownerUserID)
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.notice == nil)
        observing.cancel()
        await observing.value
    }

    @Test func aRejectedFirstMessageDoesNotBlockTheRetryFromCreatingTheThread() async throws {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let observing = Task { await viewModel.observeLiveUpdates() }
        #expect(await viewModel.send("Hello"))
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        let operation = try #require(creates.first)
        await fixture.cache.markFailed(
            ownerUserID: fixture.ownerUserID,
            clientOperationID: operation.operation.id
        )
        LocalStoreChanges.post(.dailyChat, ownerUserID: fixture.ownerUserID)
        #expect(await waitForMain { viewModel.messages.first?.sendFailed == true })

        #expect(await viewModel.send("Hello", replacingFailed: operation.operation.id))

        // The retry starts the thread again. It is not a message for a thread that never existed.
        let recreates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
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
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        let sends = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .sendThreadMessage
        )
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
        let cached = await fixture.cache.messages(
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )
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
        let creates = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: fixture.ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        #expect(creates.isEmpty)

        // 800 of them are exactly 4,000 code points.
        #expect(await viewModel.send(String(repeating: family, count: 800)))
    }

    @Test func openingAnEmptyChatOfflineDoesNotReportALoadError() async {
        let fixture = ChatTestFixture()
        await fixture.gateway.setFailure(true)
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        // No thread exists yet, so nothing failed to load and the composer still works.
        #expect(viewModel.notice == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func aKnownThreadThatCannotBeLoadedReportsALoadError() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.gateway.setFailure(true)
        let viewModel = fixture.makeViewModel()

        await viewModel.load()

        #expect(viewModel.notice == .loadFailed)
    }

    @Test func theEmptyStateWaitsForTheFirstLoadAndEndsEvenWhenChatIsUnavailable() async {
        let fixture = ChatTestFixture(question: makeChatQuestion(revealed: false))
        let viewModel = fixture.makeViewModel()
        #expect(viewModel.isLoading)

        await viewModel.load()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.notice == .unavailable)
    }

    @Test func aReadThatFinishesLateDoesNotReplaceNewerMessages() async throws {
        let fixture = ChatTestFixture()
        let service = PausingChatService(base: fixture.makeService())
        let viewModel = fixture.makeViewModel(service: service)
        await service.pauseNextRead()

        // The first read has the empty chat when it stops.
        let loading = Task { await viewModel.load() }
        #expect(await waitUntil { await service.isPaused })

        #expect(await viewModel.send("Hello"))
        #expect(viewModel.messages.map(\.body) == ["Hello"])
        // Let the reads that the send starts finish first, so only the paused one is left.
        try await Task.sleep(for: .milliseconds(50))
        await service.resumePausedRead()
        await loading.value

        #expect(viewModel.messages.map(\.body) == ["Hello"])
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

struct DailyQuestionChatReadMarkTests {
    private let me = UUID()
    private let partner = UUID()
    private let sentAt = Date(timeIntervalSince1970: 1_000)

    private func summary(threadID: UUID = UUID(), sender: UUID?) -> DailyQuestionThreadSummary {
        DailyQuestionThreadSummary(
            threadID: threadID,
            coupleID: UUID(),
            instanceID: UUID(),
            createdAt: sentAt,
            updatedAt: sentAt,
            lastMessageID: sender == nil ? nil : UUID(),
            lastMessageAt: sender == nil ? nil : sentAt,
            lastMessageSenderUserID: sender,
            lastMessageBody: sender == nil ? nil : "Hi"
        )
    }

    @Test func onlyAPartnerMessageNewerThanTheReadMarkIsUnread() {
        let fromPartner = summary(sender: partner)

        #expect(fromPartner.isUnread(by: me, readThrough: nil))
        #expect(fromPartner.isUnread(by: me, readThrough: sentAt.addingTimeInterval(-1)))
        #expect(!fromPartner.isUnread(by: me, readThrough: sentAt))
        #expect(!summary(sender: me).isUnread(by: me, readThrough: nil))
        #expect(!summary(sender: nil).isUnread(by: me, readThrough: nil))
    }

    @Test func theFileCacheKeepsTheNewestReadMarkUntilAPurge() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatReadMarks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let threadID = UUID()

        #expect(await cache.markRead(ownerUserID: me, threadID: threadID, through: sentAt))
        let movedBack = await cache.markRead(ownerUserID: me, threadID: threadID, through: sentAt - 5)
        #expect(!movedBack)
        #expect(await FileDailyQuestionChatCache(directoryURL: directory).readMarks(ownerUserID: me) == [threadID: sentAt])
        #expect(await cache.readMarks(ownerUserID: partner).isEmpty)

        await cache.clearAll()
        #expect(await cache.readMarks(ownerUserID: me).isEmpty)
    }

    @Test func aSavedReadMarkKeepsTheServerMilliseconds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatReadMarks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let threadID = UUID()
        let serverTime = try PaeoniaConvexClient.decoder.decode(Date.self, from: Data(#""2026-10-11T12:00:00.456Z""#.utf8))

        await FileDailyQuestionChatCache(directoryURL: directory).markRead(ownerUserID: me, threadID: threadID, through: serverTime)
        let readThrough = await FileDailyQuestionChatCache(directoryURL: directory).readMarks(ownerUserID: me)[threadID]

        // The thread list from the server carries the same milliseconds, so the chat stays read.
        #expect(readThrough == serverTime)
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

    @Test func handlersTellTheOpenChatAfterConfirmingAMessage() async throws {
        let fixture = ChatTestFixture()
        let recorder = ChatChangeRecorder(ownerUserID: fixture.ownerUserID)
        defer { recorder.stop() }
        let createOperation = fixture.operationProvider.makeOperation()
        let sendOperation = fixture.operationProvider.makeOperation()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)

        _ = try await CreateDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        ).send(
            pendingSnapshot(
                ownerUserID: fixture.ownerUserID,
                operation: createOperation,
                kind: .createDailyQuestionThreadWithMessage,
                payload: try JSONEncoder().encode(
                    CreateDailyQuestionThreadMessageOperationPayload(
                        instanceID: fixture.question.id,
                        coupleID: fixture.question.coupleID,
                        body: "First"
                    )
                )
            ),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )
        let changes = recorder.count
        #expect(await waitUntil { changes.value == 1 })

        _ = try await SendDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        ).send(
            pendingSnapshot(
                ownerUserID: fixture.ownerUserID,
                operation: sendOperation,
                kind: .sendThreadMessage,
                payload: try JSONEncoder().encode(
                    SendDailyQuestionThreadMessageOperationPayload(
                        instanceID: fixture.question.id,
                        coupleID: fixture.question.coupleID,
                        threadID: fixture.threadID,
                        body: "Second"
                    )
                )
            ),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )
        #expect(await waitUntil { changes.value == 2 })
    }

    @Test func sendHandlerMarksAServerRejectionAsFailedAndStopsRetrying() async throws {
        let fixture = ChatTestFixture()
        let recorder = ChatChangeRecorder(ownerUserID: fixture.ownerUserID)
        defer { recorder.stop() }
        let operation = fixture.operationProvider.makeOperation()
        await fixture.cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: fixture.threadID,
                instanceID: fixture.question.id,
                senderUserID: fixture.ownerUserID,
                body: "Second",
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: fixture.ownerUserID
        )
        await fixture.gateway.setSendError(
            PaeoniaConvexError.server(code: "23514", message: "thread message body is too long")
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
                payload: try JSONEncoder().encode(
                    SendDailyQuestionThreadMessageOperationPayload(
                        instanceID: fixture.question.id,
                        coupleID: fixture.question.coupleID,
                        threadID: fixture.threadID,
                        body: "Second"
                    )
                )
            ),
            context: chatSyncContext(ownerUserID: fixture.ownerUserID)
        )

        var isTerminal = false
        if case .terminalFailure = result { isTerminal = true }
        #expect(isTerminal)
        let cached = await fixture.cache.messages(
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )
        #expect(cached.first?.sendFailed == true)
        #expect(cached.first?.isSending == false)
        let changes = recorder.count
        #expect(await waitUntil { changes.value == 1 })
    }

    @Test func sendHandlerKeepsAConnectionErrorRetryable() async throws {
        let fixture = ChatTestFixture()
        let operation = fixture.operationProvider.makeOperation()
        await fixture.gateway.setSendError(URLError(.notConnectedToInternet))
        let handler = SendDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        )

        var threw = false
        do {
            _ = try await handler.send(
                pendingSnapshot(
                    ownerUserID: fixture.ownerUserID,
                    operation: operation,
                    kind: .sendThreadMessage,
                    payload: try JSONEncoder().encode(
                        SendDailyQuestionThreadMessageOperationPayload(
                            instanceID: fixture.question.id,
                            coupleID: fixture.question.coupleID,
                            threadID: fixture.threadID,
                            body: "Second"
                        )
                    )
                ),
                context: chatSyncContext(ownerUserID: fixture.ownerUserID)
            )
        } catch {
            threw = true
        }

        #expect(threw)
    }

    /// A message queued behind a refused thread used to retry forever.
    @Test func aRefusedThreadFailsTheMessagesWaitingForIt() async throws {
        let fixture = ChatTestFixture()
        let ownerUserID = fixture.ownerUserID
        let instanceID = fixture.question.id
        let coupleID = fixture.question.coupleID
        let otherInstanceID = UUID()
        let create = fixture.operationProvider.makeOperation()
        let waiting = fixture.operationProvider.makeOperation()
        let otherChat = fixture.operationProvider.makeOperation()
        let createData = try JSONEncoder().encode(
            CreateDailyQuestionThreadMessageOperationPayload(
                instanceID: instanceID,
                coupleID: coupleID,
                body: "First"
            )
        )

        for (operation, messageInstanceID, body) in [
            (create, instanceID, "First"),
            (waiting, instanceID, "Second"),
            (otherChat, otherInstanceID, "Other chat")
        ] {
            await fixture.cache.append(
                DailyQuestionChatMessage(
                    id: operation.id,
                    threadID: nil,
                    instanceID: messageInstanceID,
                    senderUserID: ownerUserID,
                    body: body,
                    createdAt: operation.localCreatedAt,
                    clientOperationID: operation.id,
                    isSending: true
                ),
                ownerUserID: ownerUserID
            )
        }
        try await fixture.pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: create,
                operationKind: .createDailyQuestionThreadWithMessage,
                idempotencyScope: "chat",
                requestData: createData
            )
        )
        // Both sends have no thread id yet. Only the one for the refused chat may fail.
        for (operation, sendInstanceID, body) in [
            (waiting, instanceID, "Second"),
            (otherChat, otherInstanceID, "Other chat")
        ] {
            try await fixture.pendingStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: ownerUserID,
                    operation: operation,
                    operationKind: .sendThreadMessage,
                    idempotencyScope: "chat",
                    requestData: try JSONEncoder().encode(
                        SendDailyQuestionThreadMessageOperationPayload(
                            instanceID: sendInstanceID,
                            coupleID: coupleID,
                            threadID: nil,
                            body: body
                        )
                    )
                )
            )
        }
        await fixture.gateway.setSendError(
            PaeoniaConvexError.server(code: "P0001", message: "you must answer this daily question")
        )

        let result = try await CreateDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        ).send(
            pendingSnapshot(
                ownerUserID: ownerUserID,
                operation: create,
                kind: .createDailyQuestionThreadWithMessage,
                payload: createData
            ),
            context: chatSyncContext(ownerUserID: ownerUserID, pendingStore: fixture.pendingStore)
        )

        var isTerminal = false
        if case .terminalFailure = result { isTerminal = true }
        #expect(isTerminal)
        let stillWaiting = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .sendThreadMessage
        )
        #expect(stillWaiting.map(\.operation.id) == [otherChat.id])
        let refusedChat = await fixture.cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
        #expect(refusedChat.first(where: { $0.clientOperationID == waiting.id })?.sendFailed == true)
        let untouchedChat = await fixture.cache.messages(ownerUserID: ownerUserID, instanceID: otherInstanceID)
        #expect(untouchedChat.first?.sendFailed == false)
        #expect(untouchedChat.first?.isSending == true)
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

    @Test func aSlowRefreshDoesNotDropAMessageThatArrivedWhileItWasLoading() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let gateway = fixture.gateway
        let earlier = partnerMessage(fixture, body: "Earlier", at: 5)
        let justNow = partnerMessage(fixture, body: "Just now", at: 9)
        await gateway.setRemote(summaries: [fixture.summary], messages: [earlier])
        await gateway.holdLoads()
        let owner = fixture.ownerUserID
        let instanceID = fixture.question.id
        let threadID = fixture.threadID

        let refresh = Task {
            try await service.refreshMessages(ownerUserID: owner, instanceID: instanceID, threadID: threadID)
        }
        #expect(await waitUntil { await gateway.loadCallCount == 1 })

        // The live result lands while the request is still out.
        let updates = service.liveMessageUpdates(ownerUserID: owner, instanceID: instanceID, threadID: threadID)
        var iterator = updates.makeAsyncIterator()
        await gateway.liveSource.push([earlier, justNow])
        await iterator.next()
        await gateway.releaseLoads()
        _ = try await refresh.value

        let cached = await fixture.cache.messages(ownerUserID: owner, instanceID: instanceID)
        #expect(cached.map(\.body) == ["Earlier", "Just now"])
    }

    @Test func refreshesThatFinishAfterAPurgeAreNotWrittenBack() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let gateway = fixture.gateway
        await gateway.setRemote(
            summaries: [fixture.summary],
            messages: [partnerMessage(fixture, body: "Private")]
        )
        await gateway.holdLoads()
        let owner = fixture.ownerUserID
        let instanceID = fixture.question.id
        let threadID = fixture.threadID

        let summaries = Task { try await service.refreshThreadSummaries(ownerUserID: owner) }
        let messages = Task {
            try await service.refreshMessages(ownerUserID: owner, instanceID: instanceID, threadID: threadID)
        }
        #expect(await waitUntil { await gateway.loadCallCount == 2 })

        // Sign-out clears the cache while both requests are out.
        await fixture.cache.clearAll()
        await gateway.releaseLoads()
        let refreshedSummaries = try await summaries.value
        _ = try await messages.value

        #expect(refreshedSummaries.isEmpty)
        #expect(await fixture.cache.summaries(ownerUserID: owner).isEmpty)
        #expect(await fixture.cache.messages(ownerUserID: owner, instanceID: instanceID).isEmpty)
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
            instanceID: fixture.question.id,
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
                instanceID: fixture.question.id,
                senderUserID: fixture.ownerUserID,
                body: "Hi",
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: fixture.ownerUserID
        )

        let messages = await cache.messages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id)
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
                    instanceID: fixture.question.id,
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
            instanceID: fixture.question.id
        )
        await cache.discardFailed(ownerUserID: fixture.ownerUserID, clientOperationID: failed.id)
        let afterFailedDiscard = await cache.messages(
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )

        #expect(afterSendingDiscard.count == 2)
        #expect(afterFailedDiscard.map(\.id) == [sending.id])
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
struct DailyQuestionChatVoiceTests {
    @Test func aQueuedVoiceMessageUploadsItsRecordingAndSendsTheUpload() async throws {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let service = fixture.makeService()
        let recording = Data([1, 2, 3])
        _ = try await service.queueVoiceMessage(
            ownerUserID: fixture.ownerUserID,
            coupleID: fixture.question.coupleID,
            instanceID: fixture.question.id,
            threadID: fixture.threadID,
            voice: DailyQuestionChatVoicePayload(
                messageID: fixture.messageID,
                data: recording,
                durationMs: 1_500,
                reserveOperation: fixture.operationProvider.makeOperation(),
                finalizeOperation: fixture.operationProvider.makeOperation()
            ),
            createThread: false,
            replyToMessageID: nil,
            operation: fixture.operationProvider.makeOperation()
        )

        let pending = await service.pendingMessages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id)
        #expect(pending.map(\.id) == [fixture.messageID])
        #expect(pending.first?.voice?.data == recording)

        let assetID = UUID()
        let uploader = ChatVoiceUploader(assetID: assetID)
        let queued = try #require(
            try await fixture.pendingStore.inFlightOperations(ownerUserID: fixture.ownerUserID, kind: .sendThreadMessage)
                .first
        )
        let result = try await SendDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache,
            mediaUploadService: uploader
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))

        #expect(result == .succeeded)
        #expect(await uploader.uploadedParentIDs == [fixture.messageID])
        #expect(await fixture.gateway.lastMediaAssetIDs == [assetID])
        let cached = await fixture.cache.messages(ownerUserID: fixture.ownerUserID, instanceID: fixture.question.id)
        #expect(cached.first?.isSending == false)
    }

    @Test func aConfirmedVoiceMessageKeepsPlayingFromThisPhone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatVoice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let owner = UUID()
        let operationID = UUID()
        let message = DailyQuestionChatMessage(
            id: UUID(), threadID: nil, instanceID: UUID(), senderUserID: owner, body: "",
            createdAt: Date(timeIntervalSince1970: 1), clientOperationID: operationID, isSending: true,
            voice: DailyQuestionChatVoice(data: Data([7]), durationMs: 900)
        )
        await cache.append(message, ownerUserID: owner)

        await cache.confirm(
            ownerUserID: owner, instanceID: message.instanceID, coupleID: UUID(), clientOperationID: operationID,
            threadID: UUID(), messageID: message.id, body: "", senderUserID: owner, createdAt: message.createdAt
        )

        let confirmed = try #require(await cache.messages(ownerUserID: owner, instanceID: message.instanceID).first)
        #expect(!confirmed.isSending)
        #expect(confirmed.voice == message.voice)
    }

    @Test func aPhotoMessageUploadsEachPhotoAsAChatPhotoAndSendsThemInOrder() async throws {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Earlier")],
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.prepare()
        let photos = [
            DailyQuestionChatPhoto(data: Data([1]), width: 400, height: 300),
            DailyQuestionChatPhoto(data: Data([2]), width: 300, height: 400),
        ]

        #expect(await viewModel.send("Look", photos: photos))
        let pending = viewModel.messages.last
        #expect(pending?.photos?.map(\.data) == [Data([1]), Data([2])])
        #expect(pending?.body == "Look")

        let uploader = ChatVoiceUploader(assetID: UUID())
        let queued = try #require(
            try await fixture.pendingStore.inFlightOperations(ownerUserID: fixture.ownerUserID, kind: .sendThreadMessage)
                .first
        )
        let result = try await SendDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache,
            mediaUploadService: uploader
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))

        #expect(result == .succeeded)
        #expect(await uploader.uploadedPurposes == [.threadPhoto, .threadPhoto])
        // Both photos are reserved under the message's own id, which the server requires.
        let parentIDs = await uploader.uploadedParentIDs
        #expect(Set(parentIDs).count == 1)
        #expect(parentIDs.first == pending?.id)
        #expect(await fixture.gateway.lastMediaAssetIDs?.count == 2)
    }

    @Test func aMessageWithoutTextPreviewsByItsAttachment() {
        func summary(mediaType: String?) -> DailyQuestionThreadSummary {
            DailyQuestionThreadSummary(
                threadID: UUID(), coupleID: UUID(), instanceID: UUID(), createdAt: .now, updatedAt: .now,
                lastMessageID: UUID(), lastMessageAt: .now, lastMessageSenderUserID: UUID(), lastMessageBody: nil,
                lastMessageMediaType: mediaType
            )
        }

        #expect(summary(mediaType: "image").lastMessagePreview == String(localized: .dailyChatPhotoPreview))
        #expect(summary(mediaType: "voice").lastMessagePreview == String(localized: .dailyChatVoicePreview))
    }

    @Test func theServerCopyOfAVoiceMessageIsMatchedByItsID() {
        let me = UUID()
        func pendingVoice(_ id: UUID) -> DailyQuestionChatMessage {
            DailyQuestionChatMessage(
                id: id, threadID: nil, instanceID: UUID(), senderUserID: me, body: "",
                createdAt: Date(timeIntervalSince1970: 1), clientOperationID: UUID(), isSending: true,
                voice: DailyQuestionChatVoice(data: Data([1]))
            )
        }
        let first = pendingVoice(UUID())
        let second = pendingVoice(UUID())
        let remoteSecond = DailyQuestionChatMessage(
            id: second.id, threadID: UUID(), instanceID: second.instanceID, senderUserID: me, body: "",
            createdAt: Date(timeIntervalSince1970: 2), clientOperationID: nil, isSending: false,
            voice: DailyQuestionChatVoice(mediaAssetID: UUID())
        )

        let claimed = DailyQuestionChatMessage.claimingPending(remote: [remoteSecond], cached: [], pending: [first, second])

        #expect(claimed.first?.clientOperationID == second.clientOperationID)
    }

    @Test func aMessageWithNoTextPreviewsAsAVoiceMessage() {
        func summary(body: String?, messageID: UUID?) -> DailyQuestionThreadSummary {
            DailyQuestionThreadSummary(
                threadID: UUID(), coupleID: UUID(), instanceID: UUID(), createdAt: .now, updatedAt: .now,
                lastMessageID: messageID, lastMessageAt: .now, lastMessageSenderUserID: UUID(), lastMessageBody: body
            )
        }

        #expect(summary(body: "Hi", messageID: UUID()).lastMessagePreview == "Hi")
        #expect(summary(body: nil, messageID: UUID()).lastMessagePreview == String(localized: .dailyChatVoicePreview))
        #expect(summary(body: nil, messageID: nil).lastMessagePreview == nil)
    }

    @Test func theConversationOpensWithBothAnswersOldestFirst() {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()

        #expect(viewModel.answers.count == 2)
        #expect(viewModel.answers.map(\.answeredAt) == viewModel.answers.map(\.answeredAt).sorted())
        #expect(viewModel.waitingMessage == nil)
    }

    @Test func thePageKnowsWhenItHasReadThePhonesCopyOfTheChat() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        let viewModel = fixture.makeViewModel()
        #expect(!viewModel.hasReadStore)

        await viewModel.load()

        #expect(viewModel.hasReadStore)
        #expect(viewModel.messages.isEmpty)
    }

    @Test func preparingReadsThePhonesCopyWithoutTheNetwork() async {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Saved earlier")],
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )
        let viewModel = fixture.makeViewModel()

        await viewModel.prepare()

        #expect(viewModel.hasReadStore)
        #expect(viewModel.messages.map(\.body) == ["Saved earlier"])
        #expect(await fixture.gateway.loadCallCount == 0)
    }

    @Test func aReplyGoesOutWithItsTargetAndClearsTheBanner() async throws {
        let fixture = ChatTestFixture()
        await fixture.cache.saveSummaries([fixture.summary], ownerUserID: fixture.ownerUserID)
        await fixture.cache.saveMessages(
            [fixture.remoteMessage(body: "Earlier")],
            ownerUserID: fixture.ownerUserID,
            instanceID: fixture.question.id
        )
        let viewModel = fixture.makeViewModel()
        await viewModel.prepare()
        let target = try #require(viewModel.messages.first)

        viewModel.setReplyTarget(target)
        #expect(viewModel.replyTarget?.id == target.id)
        #expect(await viewModel.send("Answering that"))
        #expect(viewModel.replyTarget == nil)

        let queued = try #require(
            try await fixture.pendingStore.inFlightOperations(ownerUserID: fixture.ownerUserID, kind: .sendThreadMessage)
                .first
        )
        _ = try await SendDailyQuestionThreadMessagePendingOperationHandler(
            gateway: fixture.gateway,
            cache: fixture.cache
        ).send(queued, context: chatSyncContext(ownerUserID: fixture.ownerUserID))
        #expect(await fixture.gateway.lastReplyToMessageID == target.id)
    }

    @Test func aMessageStillSendingCannotBeRepliedTo() {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let sending = DailyQuestionChatMessage(
            id: UUID(), threadID: nil, instanceID: fixture.question.id, senderUserID: fixture.ownerUserID,
            body: "Hi", createdAt: .now, clientOperationID: UUID(), isSending: true
        )

        viewModel.setReplyTarget(sending)

        #expect(viewModel.replyTarget == nil)
    }

    @Test func aHiddenPartnerAnswerStaysOutAndThePageSaysWhoItWaitsFor() {
        let fixture = ChatTestFixture(question: makeChatQuestion(revealed: false))
        let viewModel = fixture.makeViewModel()

        #expect(viewModel.answers.map(\.isOwnAnswer) == [true])
        #expect(!viewModel.isChatAvailable)
        #expect(viewModel.waitingMessage != nil)
    }
}

private actor ChatVoiceUploader: DailyAnswerMediaUploading {
    let assetID: UUID
    private(set) var uploadedParentIDs: [UUID] = []
    private(set) var uploadedPurposes: [DailyAnswerMediaPurpose] = []

    init(assetID: UUID) {
        self.assetID = assetID
    }

    func uploadMedia(
        _ media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        uploadedParentIDs.append(answerID)
        uploadedPurposes.append(media.purpose)
        return assetID
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

    func makeService() -> DailyQuestionChatService {
        DailyQuestionChatService(
            gateway: gateway,
            cache: cache,
            pendingOperationStore: pendingStore
        )
    }

    func makeViewModel(service: (any DailyQuestionChatServicing)? = nil) -> DailyQuestionChatViewModel {
        DailyQuestionChatViewModel(
            question: question,
            participants: DailyChallengeParticipants(
                currentUserID: ownerUserID,
                currentDisplayName: "You",
                partnerUserID: partnerUserID,
                partnerDisplayName: "Partner"
            ),
            service: service ?? makeService(),
            operationProvider: operationProvider
        )
    }

    /// A message that was saved on this phone and then rejected by the server.
    func cacheFailedMessage(_ body: String) async -> SyncClientOperation {
        let operation = operationProvider.makeOperation()
        await cache.append(
            DailyQuestionChatMessage(
                id: operation.id,
                threadID: nil,
                instanceID: question.id,
                senderUserID: ownerUserID,
                body: body,
                createdAt: operation.localCreatedAt,
                clientOperationID: operation.id,
                isSending: true
            ),
            ownerUserID: ownerUserID
        )
        await cache.markFailed(ownerUserID: ownerUserID, clientOperationID: operation.id)
        return operation
    }
}

/// Counts `.dailyChat` changes posted for one user.
private final class ChatChangeRecorder: @unchecked Sendable {
    let count = LockedBox(0)
    private var task: Task<Void, Never>?

    init(ownerUserID: UUID) {
        // The stream starts watching when it is created, so no later post is missed.
        let changes = LocalStoreChanges.changes(in: .dailyChat)
        let count = self.count
        task = Task {
            for await change in changes where change.ownerUserID == ownerUserID {
                count.mutate { $0 += 1 }
            }
        }
    }

    func stop() {
        task?.cancel()
    }
}

/// Wraps the real service and pauses one `hasPendingThreadCreation` call after it has
/// read, so a test can finish a newer read first and then let this older one return.
private actor PausingChatService: DailyQuestionChatServicing {
    private let base: DailyQuestionChatService
    private var pausesNextRead = false
    private var pausedRead: CheckedContinuation<Void, Never>?

    init(base: DailyQuestionChatService) {
        self.base = base
    }

    var isPaused: Bool {
        pausedRead != nil
    }

    func pauseNextRead() {
        pausesNextRead = true
    }

    func resumePausedRead() {
        pausedRead?.resume()
        pausedRead = nil
    }

    func hasPendingThreadCreation(ownerUserID: UUID, instanceID: UUID) async -> Bool {
        let result = await base.hasPendingThreadCreation(ownerUserID: ownerUserID, instanceID: instanceID)
        if pausesNextRead {
            pausesNextRead = false
            await withCheckedContinuation { pausedRead = $0 }
        }
        return result
    }

    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary] {
        await base.cachedThreadSummaries(ownerUserID: ownerUserID)
    }

    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary] {
        try await base.refreshThreadSummaries(ownerUserID: ownerUserID)
    }

    func cachedMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage] {
        await base.cachedMessages(ownerUserID: ownerUserID, instanceID: instanceID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        instanceID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage] {
        try await base.refreshMessages(ownerUserID: ownerUserID, instanceID: instanceID, threadID: threadID)
    }

    func pendingMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage] {
        await base.pendingMessages(ownerUserID: ownerUserID, instanceID: instanceID)
    }

    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async {
        await base.discardFailedMessage(ownerUserID: ownerUserID, clientOperationID: clientOperationID)
    }

    func queueMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        instanceID: UUID,
        threadID: UUID?,
        body: String,
        photos: DailyQuestionChatPhotosPayload?,
        createThread: Bool,
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        try await base.queueMessage(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            instanceID: instanceID,
            threadID: threadID,
            body: body,
            photos: photos,
            createThread: createThread,
            replyToMessageID: replyToMessageID,
            operation: operation
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
    private var sendError: (any Error)?
    private var holdsLoads = false
    private var heldLoads = [CheckedContinuation<Void, Never>]()
    private(set) var loadCallCount = 0
    private(set) var createCallCount = 0
    private(set) var sendCallCount = 0
    private(set) var lastMediaAssetIDs: [UUID]?
    private(set) var lastReplyToMessageID: UUID?

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

    /// Makes only the send calls fail, with the error a real server would produce.
    func setSendError(_ error: (any Error)?) {
        sendError = error
    }

    /// Makes loads stop after they read their result, so a test can change the
    /// cache while a request is out. The result is the data from before the stop.
    func holdLoads() {
        holdsLoads = true
    }

    func releaseLoads() {
        holdsLoads = false
        let waiting = heldLoads
        heldLoads = []
        waiting.forEach { $0.resume() }
    }

    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary] {
        loadCallCount += 1
        let result = summaries
        await waitWhileHeld()
        if shouldFail { throw ChatTestError.requested }
        return result
    }

    func loadMessages(threadID _: UUID, instanceID _: UUID) async throws -> [DailyQuestionChatMessage] {
        loadCallCount += 1
        let result = messages
        await waitWhileHeld()
        if shouldFail { throw ChatTestError.requested }
        return result
    }

    private func waitWhileHeld() async {
        guard holdsLoads else { return }
        await withCheckedContinuation { heldLoads.append($0) }
    }

    nonisolated func liveMessages(threadID _: UUID, instanceID _: UUID) -> AsyncStream<[DailyQuestionChatMessage]> {
        liveSource.stream()
    }

    func createThreadWithMessage(
        _: CreateDailyQuestionThreadMessageOperationPayload,
        mediaAssetIDs: [UUID],
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse {
        createCallCount += 1
        lastMediaAssetIDs = mediaAssetIDs
        if let sendError { throw sendError }
        if shouldFail { throw ChatTestError.requested }
        return DailyQuestionThreadMessageResponse(threadID: threadID, messageID: messageID)
    }

    func sendMessage(
        threadID _: UUID,
        body _: String,
        mediaAssetIDs: [UUID],
        replyToMessageID: UUID?,
        operation _: SyncClientOperation
    ) throws -> DailyQuestionThreadMessageResponse {
        sendCallCount += 1
        lastMediaAssetIDs = mediaAssetIDs
        lastReplyToMessageID = replyToMessageID
        if let sendError { throw sendError }
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
        let existing = storedMessages[ownerUserID]?[message.instanceID] ?? []
        if let operationID = message.clientOperationID,
           existing.contains(where: { $0.clientOperationID == operationID && !$0.isSending }) {
            return
        }
        storedMessages[ownerUserID, default: [:]][message.instanceID, default: []].append(message)
    }

    func markFailed(ownerUserID: UUID, clientOperationID: UUID) {
        guard let instanceIDs = storedMessages[ownerUserID]?.keys else { return }
        for instanceID in instanceIDs {
            guard
                let messages = storedMessages[ownerUserID]?[instanceID],
                let index = messages.firstIndex(where: { $0.clientOperationID == clientOperationID })
            else { continue }
            let message = messages[index]
            storedMessages[ownerUserID]?[instanceID]?[index] = DailyQuestionChatMessage(
                id: message.id,
                threadID: message.threadID,
                instanceID: message.instanceID,
                senderUserID: message.senderUserID,
                body: message.body,
                createdAt: message.createdAt,
                clientOperationID: clientOperationID,
                isSending: false,
                sendFailed: true
            )
            return
        }
    }

    func discardFailed(ownerUserID: UUID, clientOperationID: UUID) {
        guard let instanceIDs = storedMessages[ownerUserID]?.keys else { return }
        for instanceID in Array(instanceIDs) {
            storedMessages[ownerUserID]?[instanceID]?.removeAll {
                $0.clientOperationID == clientOperationID && $0.sendFailed
            }
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
            storedMessages[ownerUserID]?[instanceID]?[index] = confirmed
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

    func mergeMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        let cached = self.messages(ownerUserID: ownerUserID, instanceID: instanceID)
        saveMessages(
            DailyQuestionChatMessage.keepingNewerCached(messages, cached: cached),
            ownerUserID: ownerUserID,
            instanceID: instanceID
        )
        return true
    }

    func saveSummaries(
        _ summaries: [DailyQuestionThreadSummary],
        ownerUserID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveSummaries(summaries, ownerUserID: ownerUserID)
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
