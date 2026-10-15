import Foundation

protocol DailyQuestionChatGateway: Actor {
    func loadThreadSummaries() async throws -> [DailyQuestionThreadSummary]
    /// The newest page of the thread, or the page before `before`.
    func loadMessages(
        threadID: UUID,
        questionID: UUID,
        before: DailyQuestionChatMessageCursor?
    ) async throws -> DailyQuestionChatMessagePage
    func loadRounds(coupleID: UUID, questionID: UUID) async throws -> DailyQuestionChatRoundsRow
    /// Every result of the question's rounds query, newest state only.
    nonisolated func liveRounds(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyQuestionChatRoundsRow>
    /// Every result of the thread's newest page query, newest state only.
    nonisolated func liveMessages(threadID: UUID, questionID: UUID) -> AsyncStream<DailyQuestionChatMessagePage>
    func createThreadWithMessage(
        _ payload: CreateDailyChatThreadPayload,
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
    func setTyping(coupleID: UUID, questionID: UUID, isTyping: Bool) async throws
    func markThreadRead(threadID: UUID, messageID: UUID) async throws
    func markAnswerSeen(instanceID: UUID) async throws
    nonisolated func livePresence(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyChatPresence>
}

extension DailyQuestionChatGateway {
    func loadRounds(coupleID _: UUID, questionID _: UUID) throws -> DailyQuestionChatRoundsRow {
        throw DailyQuestionChatServiceError.unavailable
    }

    nonisolated func liveRounds(coupleID _: UUID, questionID _: UUID) -> AsyncStream<DailyQuestionChatRoundsRow> {
        AsyncStream { $0.finish() }
    }

    func editMessage(messageID _: UUID, body _: String) throws {
        throw DailyQuestionChatServiceError.unavailable
    }

    nonisolated func liveMessages(threadID _: UUID, questionID _: UUID) -> AsyncStream<DailyQuestionChatMessagePage> {
        AsyncStream { $0.finish() }
    }

    func setTyping(coupleID _: UUID, questionID _: UUID, isTyping _: Bool) throws {}
    func markThreadRead(threadID _: UUID, messageID _: UUID) throws {}
    func markAnswerSeen(instanceID _: UUID) throws {}
    nonisolated func livePresence(coupleID _: UUID, questionID _: UUID) -> AsyncStream<DailyChatPresence> {
        AsyncStream { $0.finish() }
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

    func loadMessages(
        threadID: UUID,
        questionID: UUID,
        before: DailyQuestionChatMessageCursor?
    ) async throws -> DailyQuestionChatMessagePage {
        let row: ThreadMessagesPageRow = try await client.query(
            "threads:get_thread_messages",
            args: ThreadMessagesRequest(threadID: threadID, before: before)
        )
        return row.page(questionID: questionID)
    }

    func loadRounds(coupleID: UUID, questionID: UUID) async throws -> DailyQuestionChatRoundsRow {
        try await client.query(
            "dailyQuestionChat:get_daily_question_chat",
            args: QuestionChatRequest(coupleID: coupleID, questionID: questionID)
        )
    }

    nonisolated func liveRounds(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyQuestionChatRoundsRow> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "dailyQuestionChat:get_daily_question_chat",
                    args: [
                        "p_couple_id": coupleID.uuidString.lowercased(),
                        "p_question_id": questionID.uuidString.lowercased()
                    ],
                    as: DailyQuestionChatRoundsRow.self
                )
                for await result in results {
                    if case let .value(rows) = result { continuation.yield(rows) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated func liveMessages(threadID: UUID, questionID: UUID) -> AsyncStream<DailyQuestionChatMessagePage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "threads:get_thread_messages",
                    args: [
                        "p_thread_id": threadID.uuidString.lowercased(),
                        "p_limit": Double(DailyQuestionChatMessage.pageSize)
                    ],
                    as: ThreadMessagesPageRow.self
                )
                for await result in results {
                    if case let .value(row) = result { continuation.yield(row.page(questionID: questionID)) }
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

    func setTyping(coupleID: UUID, questionID: UUID, isTyping: Bool) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:set_daily_chat_typing",
            args: TypingRequest(coupleID: coupleID, questionID: questionID, isTyping: isTyping)
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

    nonisolated func livePresence(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyChatPresence> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "chatPresence:get_daily_chat_presence",
                    args: [
                        "p_couple_id": coupleID.uuidString.lowercased(),
                        "p_question_id": questionID.uuidString.lowercased()
                    ],
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
        _ payload: CreateDailyChatThreadPayload,
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
