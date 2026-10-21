import Foundation

protocol ThreadChatGateway: Actor {
    func loadThreadSummaries() async throws -> [ThreadChatSummary]
    /// The newest page of the thread, or the page before `before`.
    func loadMessages(
        threadID: UUID,
        subjectID: UUID,
        before: ThreadChatMessageCursor?
    ) async throws -> ThreadChatMessagePage
    func loadRounds(coupleID: UUID, questionID: UUID) async throws -> DailyQuestionChatRoundsRow
    /// Every result of the question's rounds query, newest state only.
    nonisolated func liveRounds(coupleID: UUID, questionID: UUID) -> AsyncStream<DailyQuestionChatRoundsRow>
    /// Every result of the thread's newest page query, newest state only.
    nonisolated func liveMessages(threadID: UUID, subjectID: UUID) -> AsyncStream<ThreadChatMessagePage>
    func createThreadWithMessage(
        _ payload: CreateChatThreadPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessageResponse
    func sendMessage(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessageResponse
    func editMessage(messageID: UUID, body: String) async throws
    /// Takes back the user's own message for both phones. Deleting one that is already
    /// gone is fine, so a retry from the send queue is safe.
    func deleteMessage(messageID: UUID, operation: SyncClientOperation) async throws
    /// Sets the user's reaction to a message or an answer, or takes it back with nil.
    func setReaction(on item: ThreadChatItemID, emoji: String?) async throws
    func setTyping(coupleID: UUID, subject: ThreadChatSubject, isTyping: Bool) async throws
    func markThreadRead(threadID: UUID, messageID: UUID) async throws
    func markAnswerSeen(instanceID: UUID) async throws
    nonisolated func livePresence(coupleID: UUID, subject: ThreadChatSubject) -> AsyncStream<ThreadChatPresence>
}

extension ThreadChatGateway {
    func loadRounds(coupleID _: UUID, questionID _: UUID) throws -> DailyQuestionChatRoundsRow {
        throw ThreadChatServiceError.unavailable
    }

    nonisolated func liveRounds(coupleID _: UUID, questionID _: UUID) -> AsyncStream<DailyQuestionChatRoundsRow> {
        AsyncStream { $0.finish() }
    }

    func editMessage(messageID _: UUID, body _: String) throws {
        throw ThreadChatServiceError.unavailable
    }

    func deleteMessage(messageID _: UUID, operation _: SyncClientOperation) throws {
        throw ThreadChatServiceError.unavailable
    }

    func setReaction(on _: ThreadChatItemID, emoji _: String?) throws {
        throw ThreadChatServiceError.unavailable
    }

    nonisolated func liveMessages(threadID _: UUID, subjectID _: UUID) -> AsyncStream<ThreadChatMessagePage> {
        AsyncStream { $0.finish() }
    }

    func setTyping(coupleID _: UUID, subject _: ThreadChatSubject, isTyping _: Bool) throws {}
    func markThreadRead(threadID _: UUID, messageID _: UUID) throws {}
    func markAnswerSeen(instanceID _: UUID) throws {}
    nonisolated func livePresence(coupleID _: UUID, subject _: ThreadChatSubject) -> AsyncStream<ThreadChatPresence> {
        AsyncStream { $0.finish() }
    }
}

actor LiveThreadChatGateway: ThreadChatGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadThreadSummaries() async throws -> [ThreadChatSummary] {
        let rows: [ConversationThreadRow] = try await client.query(
            "threads:get_conversation_threads",
            args: PaeoniaConvexNoArgs()
        )
        return rows.compactMap(\.summary)
    }

    func loadMessages(
        threadID: UUID,
        subjectID: UUID,
        before: ThreadChatMessageCursor?
    ) async throws -> ThreadChatMessagePage {
        let row: ThreadMessagesPageRow = try await client.query(
            "threads:get_thread_messages",
            args: ThreadMessagesRequest(threadID: threadID, before: before)
        )
        return row.page(subjectID: subjectID)
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

    nonisolated func liveMessages(threadID: UUID, subjectID: UUID) -> AsyncStream<ThreadChatMessagePage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "threads:get_thread_messages",
                    args: [
                        "p_thread_id": threadID.uuidString.lowercased(),
                        "p_limit": Double(ThreadChatMessage.pageSize)
                    ],
                    as: ThreadMessagesPageRow.self
                )
                for await result in results {
                    if case let .value(row) = result { continuation.yield(row.page(subjectID: subjectID)) }
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

    func deleteMessage(messageID: UUID, operation: SyncClientOperation) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "threads:delete_thread_message",
            args: DeleteThreadMessageRequest(messageID: messageID, operation: GameClientOperationFields(operation))
        )
    }

    func setTyping(coupleID: UUID, subject: ThreadChatSubject, isTyping: Bool) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:set_chat_typing",
            args: TypingRequest(coupleID: coupleID, subject: subject, isTyping: isTyping)
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

    nonisolated func livePresence(coupleID: UUID, subject: ThreadChatSubject) -> AsyncStream<ThreadChatPresence> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let results = live.subscribe(
                    "chatPresence:get_chat_presence",
                    args: [
                        "p_couple_id": coupleID.uuidString.lowercased(),
                        "p_subject_kind": subject.kind.rawValue,
                        "p_subject_id": subject.id.uuidString.lowercased()
                    ],
                    as: PresenceRow.self
                )
                var latest = ThreadChatPresence.none
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
        _ payload: CreateChatThreadPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessageResponse {
        try await PaeoniaSignedIn.require(isSignedIn)
        let rows: [ThreadChatMessageResponse] = try await client.mutation(
            payload.subject.kind.createThreadFunction,
            args: CreateThreadMessageRequest(payload: payload, mediaAssetIDs: mediaAssetIDs, operation: operation)
        )
        guard let response = rows.first else { throw ThreadChatServiceError.missingResponse }
        return response
    }

    func sendMessage(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) async throws -> ThreadChatMessageResponse {
        try await PaeoniaSignedIn.require(isSignedIn)
        let rows: [ThreadChatMessageResponse] = try await client.mutation(
            "threads:send_thread_message",
            args: SendThreadMessageRequest(
                threadID: threadID,
                body: body,
                mediaAssetIDs: mediaAssetIDs,
                replyTo: replyTo,
                operation: operation
            )
        )
        guard let response = rows.first else { throw ThreadChatServiceError.missingResponse }
        return response
    }

    func setReaction(on item: ThreadChatItemID, emoji: String?) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await LiveReactionGateway(client: client).setReaction(emoji, on: item.reactionTarget)
    }
}
