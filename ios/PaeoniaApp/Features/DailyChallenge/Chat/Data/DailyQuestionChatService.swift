import Foundation

protocol DailyQuestionChatServicing: Actor {
    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary]
    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary]
    func cachedMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage]
    func refreshMessages(
        ownerUserID: UUID,
        instanceID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage]
    /// Follows one thread's messages while the caller iterates. Each result is
    /// merged into the chat cache before the stream yields, so the caller re-reads
    /// the cache. The stream ends when the caller's task is cancelled.
    nonisolated func liveMessageUpdates(ownerUserID: UUID, instanceID: UUID, threadID: UUID) -> AsyncStream<Void>
    /// When the user last saw each thread on this phone, keyed by thread id.
    func chatReadMarks(ownerUserID: UUID) async -> [UUID: Date]
    /// Records that the user has seen the thread up to `date`, and tells the
    /// unread badges to update when that moved the mark forward.
    func markThreadRead(ownerUserID: UUID, threadID: UUID, through date: Date) async
    /// Questions whose page the user has opened since the partner's answer showed up,
    /// on this phone.
    func seenPartnerAnswers(ownerUserID: UUID) async -> Set<UUID>
    /// Records that the user has seen the partner's answer, and tells the cards to
    /// update when that is new.
    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) async
    func pendingMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage]
    func hasPendingThreadCreation(ownerUserID: UUID, instanceID: UUID) async -> Bool
    /// Removes a message that failed to send, so the retry replaces it.
    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async
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
    ) async throws -> DailyQuestionChatMessage
    /// Queues a voice message. The recording travels in the queued operation, so it
    /// still sends after the app closes or the phone goes offline.
    func queueVoiceMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        instanceID: UUID,
        threadID: UUID?,
        voice: DailyQuestionChatVoicePayload,
        createThread: Bool,
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage
    /// Replaces the text of the user's own message. The live message query brings the
    /// change to both phones. Throws `DailyQuestionChatEditWindowClosedError` once the
    /// server says the five minutes are over.
    func editMessage(messageID: UUID, body: String) async throws
    /// Tells the partner's phone this person is typing in the chat, or has stopped.
    func setTyping(instanceID: UUID, isTyping: Bool) async
    /// Tells the server this person has read the thread up to `messageID`, for read receipts.
    func markThreadReadOnServer(threadID: UUID, messageID: UUID) async
    /// Tells the server this person has seen the partner's answer, so it stops showing
    /// as new on their other devices and the partner sees it was read. Returns whether
    /// the server took it.
    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID: UUID) async -> Bool
    /// Follows the partner's typing and read state while the caller iterates.
    nonisolated func livePresence(instanceID: UUID) -> AsyncStream<DailyChatPresence>
}

/// The partner's typing and read state in one question's chat.
nonisolated struct DailyChatPresence: Equatable, Sendable {
    var partnerIsTyping = false
    var partnerLastReadMessageID: UUID?

    static let none = DailyChatPresence()
}

extension DailyQuestionChatServicing {
    func editMessage(messageID _: UUID, body _: String) async throws {
        throw DailyQuestionChatServiceError.unavailable
    }

    func setTyping(instanceID _: UUID, isTyping _: Bool) async {}
    func markThreadReadOnServer(threadID _: UUID, messageID _: UUID) async {}
    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID _: UUID) async -> Bool { true }
    nonisolated func livePresence(instanceID _: UUID) -> AsyncStream<DailyChatPresence> {
        AsyncStream { $0.finish() }
    }

    func queueVoiceMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        instanceID _: UUID,
        threadID _: UUID?,
        voice _: DailyQuestionChatVoicePayload,
        createThread _: Bool,
        replyToMessageID _: UUID?,
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage { throw DailyQuestionChatServiceError.unavailable }

    func chatReadMarks(ownerUserID _: UUID) async -> [UUID: Date] { [:] }
    func markThreadRead(ownerUserID _: UUID, threadID _: UUID, through _: Date) async {}
    func seenPartnerAnswers(ownerUserID _: UUID) async -> Set<UUID> { [] }
    func markPartnerAnswerSeen(ownerUserID _: UUID, instanceID _: UUID) async {}

    /// Services without a live connection (previews, scenarios) have nothing to follow.
    nonisolated func liveMessageUpdates(ownerUserID _: UUID, instanceID _: UUID, threadID _: UUID) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

protocol DailyQuestionChatGateway: Actor {
    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary]
    func loadMessages(threadID: UUID, instanceID: UUID) async throws -> [DailyQuestionChatMessage]
    /// Every result of the thread's messages query, newest state only.
    nonisolated func liveMessages(threadID: UUID, instanceID: UUID) -> AsyncStream<[DailyQuestionChatMessage]>
    func createThreadWithMessage(
        _ payload: CreateDailyQuestionThreadMessageOperationPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse
    func sendMessage(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse
    func editMessage(messageID: UUID, body: String) async throws
    func setTyping(instanceID: UUID, isTyping: Bool) async throws
    func markThreadRead(threadID: UUID, messageID: UUID) async throws
    func markAnswerSeen(instanceID: UUID) async throws
    nonisolated func livePresence(instanceID: UUID) -> AsyncStream<DailyChatPresence>
}

extension DailyQuestionChatGateway {
    func editMessage(messageID _: UUID, body _: String) async throws {
        throw DailyQuestionChatServiceError.unavailable
    }

    nonisolated func liveMessages(threadID _: UUID, instanceID _: UUID) -> AsyncStream<[DailyQuestionChatMessage]> {
        AsyncStream { $0.finish() }
    }

    func setTyping(instanceID _: UUID, isTyping _: Bool) async throws {}
    func markThreadRead(threadID _: UUID, messageID _: UUID) async throws {}
    func markAnswerSeen(instanceID _: UUID) async throws {}
    nonisolated func livePresence(instanceID _: UUID) -> AsyncStream<DailyChatPresence> {
        AsyncStream { $0.finish() }
    }
}

actor DailyQuestionChatService: DailyQuestionChatServicing {
    private let gateway: any DailyQuestionChatGateway
    private let cache: any DailyQuestionChatCaching
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let encoder = JSONEncoder()

    init(
        gateway: any DailyQuestionChatGateway,
        cache: any DailyQuestionChatCaching,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.gateway = gateway
        self.cache = cache
        self.pendingOperationStore = pendingOperationStore
    }

    func cachedThreadSummaries(ownerUserID: UUID) async -> [DailyQuestionThreadSummary] {
        await cache.summaries(ownerUserID: ownerUserID)
    }

    func refreshThreadSummaries(ownerUserID: UUID) async throws -> [DailyQuestionThreadSummary] {
        // Read before the request, so a purge that runs while it is in flight
        // makes the save a no-op.
        let generation = await cache.purgeGeneration()
        let summaries = try await gateway.loadThreadSummaries()
        guard await cache.saveSummaries(
            summaries,
            ownerUserID: ownerUserID,
            unlessPurgedSince: generation
        ) else { return [] }
        return summaries
    }

    func cachedMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage] {
        await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
    }

    func refreshMessages(
        ownerUserID: UUID,
        instanceID: UUID,
        threadID: UUID
    ) async throws -> [DailyQuestionChatMessage] {
        let generation = await cache.purgeGeneration()
        let messages = try await gateway.loadMessages(threadID: threadID, instanceID: instanceID)
        let cached = await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
        let pending = await pendingMessages(ownerUserID: ownerUserID, instanceID: instanceID)
        // Live results can land while the request is in flight. The cache merge keeps
        // the ones this read is too old to contain.
        await cache.mergeMessages(
            DailyQuestionChatMessage.claimingPending(remote: messages, cached: cached, pending: pending),
            ownerUserID: ownerUserID,
            instanceID: instanceID,
            unlessPurgedSince: generation
        )
        return await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
    }

    nonisolated func liveMessageUpdates(
        ownerUserID: UUID,
        instanceID: UUID,
        threadID: UUID
    ) -> AsyncStream<Void> {
        let results = gateway.liveMessages(threadID: threadID, instanceID: instanceID)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                // Read before the first result, so a purge that starts while this
                // writer is suspended makes every later save a no-op.
                let generation = await cache.purgeGeneration()
                for await remote in results {
                    guard !Task.isCancelled else { break }
                    guard await saveLiveMessages(
                        remote,
                        ownerUserID: ownerUserID,
                        instanceID: instanceID,
                        purgeGeneration: generation
                    ) else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func saveLiveMessages(
        _ remote: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        instanceID: UUID,
        purgeGeneration: Int
    ) async -> Bool {
        let cached = await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
        let pending = await pendingMessages(ownerUserID: ownerUserID, instanceID: instanceID)
        // The screen's task is cancelled on sign-out and account switch, but nothing
        // waits for this writer. Stop here, and let the cache refuse the save if a
        // purge ran since the subscription started.
        guard !Task.isCancelled else { return false }
        return await cache.saveMessages(
            DailyQuestionChatMessage.claimingPending(remote: remote, cached: cached, pending: pending),
            ownerUserID: ownerUserID,
            instanceID: instanceID,
            unlessPurgedSince: purgeGeneration
        )
    }

    func pendingMessages(ownerUserID: UUID, instanceID: UUID) async -> [DailyQuestionChatMessage] {
        async let creates = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )
        async let sends = pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .sendThreadMessage
        )

        let createMessages = (try? await creates) ?? []
        let sendMessages = (try? await sends) ?? []
        return (createMessages + sendMessages).compactMap { pendingMessage($0, instanceID: instanceID) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func hasPendingThreadCreation(ownerUserID: UUID, instanceID: UUID) async -> Bool {
        let operations = (try? await pendingOperationStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .createDailyQuestionThreadWithMessage
        )) ?? []
        guard !operations.isEmpty else { return false }
        // The handler marks a rejected message failed before the drain records the
        // operation as finished. That operation is no longer creating the thread.
        let cached = await cache.messages(ownerUserID: ownerUserID, instanceID: instanceID)
        let failedOperationIDs = Set(cached.filter(\.sendFailed).compactMap(\.clientOperationID))
        return operations.contains { operation in
            guard !failedOperationIDs.contains(operation.operation.id),
                  let data = operation.requestData,
                  let payload = try? JSONDecoder().decode(
                    CreateDailyQuestionThreadMessageOperationPayload.self,
                    from: data
                  ) else { return false }
            return payload.instanceID == instanceID
        }
    }

    func discardFailedMessage(ownerUserID: UUID, clientOperationID: UUID) async {
        await cache.discardFailed(ownerUserID: ownerUserID, clientOperationID: clientOperationID)
    }

    func chatReadMarks(ownerUserID: UUID) async -> [UUID: Date] {
        await cache.readMarks(ownerUserID: ownerUserID)
    }

    // An edit is not queued. It only makes sense within minutes of sending, so a
    // failure leaves the text in the message box for the person to try again.
    func editMessage(messageID: UUID, body: String) async throws {
        do {
            try await gateway.editMessage(messageID: messageID, body: body)
        } catch {
            if String(describing: error).contains("messages can only be edited for 5 minutes") {
                throw DailyQuestionChatEditWindowClosedError()
            }
            throw error
        }
    }

    // Typing and read receipts are live hints, so a failed call is dropped rather than
    // queued. The next keystroke or the next message tries again.
    func setTyping(instanceID: UUID, isTyping: Bool) async {
        try? await gateway.setTyping(instanceID: instanceID, isTyping: isTyping)
    }

    func markThreadReadOnServer(threadID: UUID, messageID: UUID) async {
        try? await gateway.markThreadRead(threadID: threadID, messageID: messageID)
    }

    @discardableResult
    func markPartnerAnswerSeenOnServer(instanceID: UUID) async -> Bool {
        (try? await gateway.markAnswerSeen(instanceID: instanceID)) != nil
    }

    nonisolated func livePresence(instanceID: UUID) -> AsyncStream<DailyChatPresence> {
        gateway.livePresence(instanceID: instanceID)
    }

    func markThreadRead(ownerUserID: UUID, threadID: UUID, through date: Date) async {
        guard await cache.markRead(ownerUserID: ownerUserID, threadID: threadID, through: date) else { return }
        LocalStoreChanges.post(.dailyChat, ownerUserID: ownerUserID)
    }

    func seenPartnerAnswers(ownerUserID: UUID) async -> Set<UUID> {
        await cache.seenPartnerAnswers(ownerUserID: ownerUserID)
    }

    func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) async {
        guard await cache.markPartnerAnswerSeen(ownerUserID: ownerUserID, instanceID: instanceID) else { return }
        LocalStoreChanges.post(.dailyChat, ownerUserID: ownerUserID)
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
        try await enqueue(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            instanceID: instanceID,
            threadID: threadID,
            body: body,
            voice: nil,
            photos: photos,
            createThread: createThread,
            replyToMessageID: replyToMessageID,
            operation: operation
        )
    }

    func queueVoiceMessage(
        ownerUserID: UUID,
        coupleID: UUID,
        instanceID: UUID,
        threadID: UUID?,
        voice: DailyQuestionChatVoicePayload,
        createThread: Bool,
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        try await enqueue(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            instanceID: instanceID,
            threadID: threadID,
            body: "",
            voice: voice,
            photos: nil,
            createThread: createThread,
            replyToMessageID: replyToMessageID,
            operation: operation
        )
    }

    private func enqueue(
        ownerUserID: UUID,
        coupleID: UUID,
        instanceID: UUID,
        threadID: UUID?,
        body: String,
        voice: DailyQuestionChatVoicePayload?,
        photos: DailyQuestionChatPhotosPayload?,
        createThread: Bool,
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage {
        let requestData: Data
        let operationKind: SyncPendingOperationKind
        if createThread {
            operationKind = .createDailyQuestionThreadWithMessage
            requestData = try encoder.encode(
                CreateDailyQuestionThreadMessageOperationPayload(
                    instanceID: instanceID,
                    coupleID: coupleID,
                    body: body,
                    voice: voice,
                    photos: photos
                )
            )
        } else {
            operationKind = .sendThreadMessage
            requestData = try encoder.encode(
                SendDailyQuestionThreadMessageOperationPayload(
                    instanceID: instanceID,
                    coupleID: coupleID,
                    threadID: threadID,
                    body: body,
                    voice: voice,
                    photos: photos,
                    replyToMessageID: replyToMessageID
                )
            )
        }

        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: operationKind,
                idempotencyScope: "daily-question-chat:\(instanceID.uuidString.lowercased())",
                requestData: requestData
            )
        )

        let message = DailyQuestionChatMessage(
            id: voice?.messageID ?? photos?.messageID ?? operation.id,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: ownerUserID,
            body: body,
            createdAt: operation.localCreatedAt,
            clientOperationID: operation.id,
            isSending: true,
            voice: voice?.pendingVoice,
            photos: photos?.pendingPhotos,
            // The first message creates the thread, so there is nothing to reply to yet.
            replyToMessageID: createThread ? nil : replyToMessageID
        )
        await cache.append(message, ownerUserID: ownerUserID)
        return message
    }

    private func pendingMessage(
        _ operation: PendingSyncOperationSnapshot,
        instanceID: UUID
    ) -> DailyQuestionChatMessage? {
        guard let data = operation.requestData else { return nil }

        let body: String
        let messageThreadID: UUID?
        let voice: DailyQuestionChatVoicePayload?
        let photos: DailyQuestionChatPhotosPayload?
        var replyToMessageID: UUID?
        switch operation.operationKind {
        case .createDailyQuestionThreadWithMessage:
            guard let payload = try? JSONDecoder().decode(
                CreateDailyQuestionThreadMessageOperationPayload.self,
                from: data
            ), payload.instanceID == instanceID else { return nil }
            body = payload.body
            messageThreadID = nil
            voice = payload.voice
            photos = payload.photos
        case .sendThreadMessage:
            guard let payload = try? JSONDecoder().decode(
                SendDailyQuestionThreadMessageOperationPayload.self,
                from: data
            ), payload.instanceID == instanceID else { return nil }
            body = payload.body
            messageThreadID = payload.threadID
            voice = payload.voice
            photos = payload.photos
            replyToMessageID = payload.replyToMessageID
        default:
            return nil
        }

        return DailyQuestionChatMessage(
            id: voice?.messageID ?? photos?.messageID ?? operation.operation.id,
            threadID: messageThreadID,
            instanceID: instanceID,
            senderUserID: operation.ownerUserID,
            body: body,
            createdAt: operation.operation.localCreatedAt,
            clientOperationID: operation.operation.id,
            isSending: true,
            isHeldOnPhone: operation.hasFailedAttempt,
            voice: voice?.pendingVoice,
            photos: photos?.pendingPhotos,
            replyToMessageID: replyToMessageID
        )
    }
}

actor LiveDailyQuestionChatGateway: DailyQuestionChatGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary] {
        let rows: [ConversationThreadRow] = try await client.query(
            "threads:get_conversation_threads",
            args: PaeoniaConvexNoArgs()
        )
        return rows.compactMap(\.dailyQuestionSummary)
    }

    func loadMessages(threadID: UUID, instanceID: UUID) async throws -> [DailyQuestionChatMessage] {
        let rows: [ThreadMessageRow] = try await client.query(
            "threads:get_thread_messages",
            args: ThreadMessagesRequest(threadID: threadID)
        )
        return rows.compactMap { $0.message(instanceID: instanceID) }
    }

    nonisolated func liveMessages(threadID: UUID, instanceID: UUID) -> AsyncStream<[DailyQuestionChatMessage]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "threads:get_thread_messages",
                    args: ["p_thread_id": threadID.uuidString.lowercased()],
                    as: [ThreadMessageRow].self
                )
                for await result in results {
                    if case let .value(rows) = result {
                        continuation.yield(rows.compactMap { $0.message(instanceID: instanceID) })
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func editMessage(messageID: UUID, body: String) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "threads:edit_thread_message",
            args: EditThreadMessageRequest(messageID: messageID, body: body)
        )
    }

    func setTyping(instanceID: UUID, isTyping: Bool) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:set_daily_chat_typing",
            args: TypingRequest(instanceID: instanceID, isTyping: isTyping)
        )
    }

    func markThreadRead(threadID: UUID, messageID: UUID) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:mark_thread_read",
            args: MarkThreadReadRequest(threadID: threadID, messageID: messageID)
        )
    }

    func markAnswerSeen(instanceID: UUID) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:mark_daily_answer_seen",
            args: MarkAnswerSeenRequest(instanceID: instanceID)
        )
    }

    nonisolated func livePresence(instanceID: UUID) -> AsyncStream<DailyChatPresence> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "chatPresence:get_daily_chat_presence",
                    args: ["p_instance_id": instanceID.uuidString.lowercased()],
                    as: PresenceRow.self
                )
                var latest = DailyChatPresence.none
                for await result in results {
                    switch result {
                    case let .value(row):
                        latest = row.presence
                    case .failure:
                        // While the subscription is down, nobody can say the partner
                        // still types. Keep the read mark.
                        latest.partnerIsTyping = false
                    }
                    continuation.yield(latest)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func createThreadWithMessage(
        _ payload: CreateDailyQuestionThreadMessageOperationPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse {
        try await PaeoniaSignedIn.require(isSignedIn)
        let rows: [DailyQuestionThreadMessageResponse] = try await client.mutation(
            "threads:create_daily_question_thread_with_message",
            args: CreateThreadMessageRequest(payload: payload, mediaAssetIDs: mediaAssetIDs, operation: operation)
        )
        guard let response = rows.first else { throw DailyQuestionChatServiceError.missingResponse }
        return response
    }

    func sendMessage(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse {
        try await PaeoniaSignedIn.require(isSignedIn)
        let rows: [DailyQuestionThreadMessageResponse] = try await client.mutation(
            "threads:send_thread_message",
            args: SendThreadMessageRequest(
                threadID: threadID,
                body: body,
                mediaAssetIDs: mediaAssetIDs,
                replyToMessageID: replyToMessageID,
                operation: operation
            )
        )
        guard let response = rows.first else { throw DailyQuestionChatServiceError.missingResponse }
        return response
    }
}

/// The server refused an edit because the message is older than five minutes.
nonisolated struct DailyQuestionChatEditWindowClosedError: Error, Equatable, Sendable {}

nonisolated enum DailyQuestionChatServiceError: Error, Equatable, Sendable {
    case unavailable
    case missingResponse
    case missingThread
}

nonisolated enum DailyQuestionChatServiceFactory {
    static func makeDefault() -> any DailyQuestionChatServicing {
        let pendingStore: any PendingSyncOperationPersisting
        if let localStore = PaeoniaLocalStore.shared {
            pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        } else {
            pendingStore = InMemoryPendingSyncOperationRepository()
        }

        let gateway: any DailyQuestionChatGateway
        if let client = try? PaeoniaConvexClientProvider.shared.client() {
            gateway = LiveDailyQuestionChatGateway(client: client)
        } else {
            gateway = UnavailableDailyQuestionChatGateway()
        }
        return DailyQuestionChatService(
            gateway: gateway,
            cache: FileDailyQuestionChatCache.shared,
            pendingOperationStore: pendingStore
        )
    }
}

actor EmptyDailyQuestionChatService: DailyQuestionChatServicing {
    func cachedThreadSummaries(ownerUserID _: UUID) async -> [DailyQuestionThreadSummary] { [] }
    func refreshThreadSummaries(ownerUserID _: UUID) async throws -> [DailyQuestionThreadSummary] { [] }
    func cachedMessages(ownerUserID _: UUID, instanceID _: UUID) async -> [DailyQuestionChatMessage] { [] }
    func refreshMessages(
        ownerUserID _: UUID,
        instanceID _: UUID,
        threadID _: UUID
    ) async throws -> [DailyQuestionChatMessage] { [] }
    func pendingMessages(ownerUserID _: UUID, instanceID _: UUID) async -> [DailyQuestionChatMessage] { [] }
    func hasPendingThreadCreation(ownerUserID _: UUID, instanceID _: UUID) async -> Bool { false }
    func discardFailedMessage(ownerUserID _: UUID, clientOperationID _: UUID) async {}
    func queueMessage(
        ownerUserID _: UUID,
        coupleID _: UUID,
        instanceID _: UUID,
        threadID _: UUID?,
        body _: String,
        photos _: DailyQuestionChatPhotosPayload?,
        createThread _: Bool,
        replyToMessageID _: UUID?,
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionChatMessage { throw DailyQuestionChatServiceError.unavailable }
}

private actor UnavailableDailyQuestionChatGateway: DailyQuestionChatGateway {
    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary] { throw DailyQuestionChatServiceError.unavailable }
    func loadMessages(threadID _: UUID, instanceID _: UUID) async throws -> [DailyQuestionChatMessage] { throw DailyQuestionChatServiceError.unavailable }
    func createThreadWithMessage(
        _: CreateDailyQuestionThreadMessageOperationPayload,
        mediaAssetIDs _: [UUID],
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse { throw DailyQuestionChatServiceError.unavailable }
    func sendMessage(
        threadID _: UUID,
        body _: String,
        mediaAssetIDs _: [UUID],
        replyToMessageID _: UUID?,
        operation _: SyncClientOperation
    ) async throws -> DailyQuestionThreadMessageResponse { throw DailyQuestionChatServiceError.unavailable }
}

nonisolated struct ConversationThreadRow: Decodable {
    let threadID: UUID
    let coupleID: UUID
    let kind: String
    let dailyQuestionInstanceID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let moderationStatus: String
    let lastMessageID: UUID?
    let lastMessageAt: Date?
    let lastMessageSenderUserID: UUID?
    let lastMessageDeletedAt: Date?
    let lastMessageModerationStatus: String?
    let lastMessageBody: String?
    let lastMessageMediaType: String?
    /// How far this user has read the chat, from any of their devices.
    let viewerReadThroughAt: Date?

    var dailyQuestionSummary: DailyQuestionThreadSummary? {
        guard kind == "daily_question", deletedAt == nil, moderationStatus == "visible",
              let dailyQuestionInstanceID else { return nil }
        let previewIsVisible = lastMessageDeletedAt == nil
            && lastMessageModerationStatus == "visible"
        return DailyQuestionThreadSummary(
            threadID: threadID,
            coupleID: coupleID,
            instanceID: dailyQuestionInstanceID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageID: previewIsVisible ? lastMessageID : nil,
            lastMessageAt: previewIsVisible ? lastMessageAt : nil,
            lastMessageSenderUserID: previewIsVisible ? lastMessageSenderUserID : nil,
            lastMessageBody: previewIsVisible ? lastMessageBody : nil,
            lastMessageMediaType: previewIsVisible ? lastMessageMediaType : nil,
            viewerReadThroughAt: viewerReadThroughAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case coupleID = "couple_id"
        case kind
        case dailyQuestionInstanceID = "daily_question_instance_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case moderationStatus = "moderation_status"
        case lastMessageID = "last_message_id"
        case lastMessageAt = "last_message_at"
        case lastMessageSenderUserID = "last_message_sender_user_id"
        case lastMessageDeletedAt = "last_message_deleted_at"
        case lastMessageModerationStatus = "last_message_moderation_status"
        case lastMessageBody = "last_message_body"
        case lastMessageMediaType = "last_message_media_type"
        case viewerReadThroughAt = "viewer_read_through_at"
    }
}

nonisolated private struct ThreadMessageRow: Decodable {
    let threadID: UUID
    let messageID: UUID
    let senderUserID: UUID
    let body: String?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?
    let moderationStatus: String
    let mediaAssetIDs: [UUID]?
    let media: [MediaRow]?
    let replyToMessageID: UUID?

    nonisolated struct MediaRow: Decodable {
        let mediaAssetID: UUID
        let mediaType: String
        let width: Int?
        let height: Int?
        let durationMs: Int?

        enum CodingKeys: String, CodingKey {
            case mediaAssetID = "media_asset_id"
            case mediaType = "media_type"
            case width
            case height
            case durationMs = "duration_ms"
        }
    }

    func message(instanceID: UUID) -> DailyQuestionChatMessage? {
        guard deletedAt == nil, moderationStatus == "visible" else { return nil }
        // A server without media details only ever had voice messages in these chats.
        let media = media ?? (mediaAssetIDs ?? []).map {
            MediaRow(mediaAssetID: $0, mediaType: "voice", width: nil, height: nil, durationMs: nil)
        }
        let voice = media.first { $0.mediaType == "voice" }.map {
            DailyQuestionChatVoice(mediaAssetID: $0.mediaAssetID, durationMs: $0.durationMs)
        }
        let photos = media.filter { $0.mediaType == "image" }.map {
            DailyQuestionChatPhoto(mediaAssetID: $0.mediaAssetID, width: $0.width, height: $0.height)
        }
        guard body != nil || voice != nil || !photos.isEmpty else { return nil }
        return DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: senderUserID,
            body: body ?? "",
            createdAt: createdAt,
            clientOperationID: nil,
            isSending: false,
            voice: voice,
            photos: photos.isEmpty ? nil : photos,
            replyToMessageID: replyToMessageID,
            editedAt: editedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case messageID = "message_id"
        case senderUserID = "sender_user_id"
        case body
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
        case moderationStatus = "moderation_status"
        case mediaAssetIDs = "media_asset_ids"
        case media
        case replyToMessageID = "reply_to_message_id"
    }
}

nonisolated private struct EditThreadMessageRequest: Encodable {
    let messageID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case body = "p_body"
    }
}

nonisolated private struct TypingRequest: Encodable {
    let instanceID: UUID
    let isTyping: Bool
    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case isTyping = "p_is_typing"
    }
}

nonisolated private struct MarkThreadReadRequest: Encodable {
    let threadID: UUID
    let messageID: UUID
    enum CodingKeys: String, CodingKey {
        case threadID = "p_thread_id"
        case messageID = "p_message_id"
    }
}

nonisolated private struct MarkAnswerSeenRequest: Encodable {
    let instanceID: UUID
    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
    }
}

nonisolated private struct PresenceRow: Decodable {
    let partnerTyping: Bool
    let partnerLastReadMessageID: UUID?

    var presence: DailyChatPresence {
        DailyChatPresence(partnerIsTyping: partnerTyping, partnerLastReadMessageID: partnerLastReadMessageID)
    }

    enum CodingKeys: String, CodingKey {
        case partnerTyping = "partner_typing"
        case partnerLastReadMessageID = "partner_last_read_message_id"
    }
}

nonisolated private struct ThreadMessagesRequest: Encodable {
    let threadID: UUID
    enum CodingKeys: String, CodingKey { case threadID = "p_thread_id" }
}

nonisolated private struct CreateThreadMessageRequest: Encodable {
    let instanceID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        payload: CreateDailyQuestionThreadMessageOperationPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) {
        instanceID = payload.instanceID
        body = payload.body
        self.mediaAssetIDs = mediaAssetIDs
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct SendThreadMessageRequest: Encodable {
    let threadID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
    /// Left out of the request when nil, so a plain send matches what servers
    /// without replies accept.
    let replyToMessageID: UUID?
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyToMessageID: UUID?,
        operation: SyncClientOperation
    ) {
        self.threadID = threadID
        self.body = body
        self.mediaAssetIDs = mediaAssetIDs
        self.replyToMessageID = replyToMessageID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "p_thread_id"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case replyToMessageID = "p_reply_to_message_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
