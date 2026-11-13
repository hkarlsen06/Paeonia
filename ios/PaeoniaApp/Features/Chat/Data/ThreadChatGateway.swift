import Foundation

protocol ThreadChatGateway: Actor {
    func loadGameTimeline(subject: GameChatSubject, before: GameChatTimelineCursor?) async throws -> GameChatTimeline
    nonisolated func liveGameTimeline(subject: GameChatSubject) -> AsyncStream<GameChatTimeline>

    func loadGameResult(coupleID: UUID, source: GameConversationSource) async throws -> GameConversationResult?
    nonisolated func liveGameResults(coupleID: UUID, source: GameConversationSource)
        -> AsyncStream<GameConversationResult?>
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
    func setChatOpen(coupleID: UUID, subject: ThreadChatSubject, isOpen: Bool) async throws
    func markThreadRead(threadID: UUID, messageID: UUID) async throws
    func markAnswerSeen(instanceID: UUID) async throws
    nonisolated func livePresence(coupleID: UUID, subject: ThreadChatSubject) -> AsyncStream<ThreadChatPresence>
}

extension ThreadChatGateway {
    func loadGameTimeline(subject _: GameChatSubject, before _: GameChatTimelineCursor?) throws -> GameChatTimeline {
        throw ThreadChatServiceError.unavailable
    }
    nonisolated func liveGameTimeline(subject _: GameChatSubject) -> AsyncStream<GameChatTimeline> {
        AsyncStream { $0.finish() }
    }

    func loadGameResult(coupleID _: UUID, source _: GameConversationSource) throws -> GameConversationResult? {
        throw ThreadChatServiceError.unavailable
    }

    nonisolated func liveGameResults(coupleID _: UUID, source _: GameConversationSource)
        -> AsyncStream<GameConversationResult?>
    {
        AsyncStream { $0.finish() }
    }

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
    func setChatOpen(coupleID _: UUID, subject _: ThreadChatSubject, isOpen _: Bool) throws {}
    func markThreadRead(threadID _: UUID, messageID _: UUID) throws {}
    func markAnswerSeen(instanceID _: UUID) throws {}
    nonisolated func livePresence(coupleID _: UUID, subject _: ThreadChatSubject) -> AsyncStream<ThreadChatPresence> {
        AsyncStream { $0.finish() }
    }
}

actor LiveThreadChatGateway: ThreadChatGateway {
    let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadGameResult(coupleID: UUID, source: GameConversationSource) async throws -> GameConversationResult? {
        try await client.query(
            "gameConversations:get_game_conversation", args: GameConversationRequest(coupleID: coupleID, source: source)
        )
    }

    nonisolated func liveGameResults(coupleID: UUID, source: GameConversationSource)
        -> AsyncStream<GameConversationResult?>
    {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let live = LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
                let updates = live.subscribe(
                    "gameConversations:get_game_conversation",
                    args: ["p_couple_id": coupleID.uuidString.lowercased(), "p_source": source],
                    as: GameConversationResult?.self)
                for await update in updates {
                    guard !Task.isCancelled else { break }
                    if case .value(let result) = update { continuation.yield(result) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
            args: DeleteThreadMessageRequest(messageID: messageID, operation: ClientOperationFields(operation))
        )
    }

    func setTyping(coupleID: UUID, subject: ThreadChatSubject, isTyping: Bool) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:set_chat_typing",
            args: ChatPresenceRequest(coupleID: coupleID, subject: subject, flag: .typing(isTyping))
        )
    }

    func setChatOpen(coupleID: UUID, subject: ThreadChatSubject, isOpen: Bool) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "chatPresence:set_chat_open",
            args: ChatPresenceRequest(coupleID: coupleID, subject: subject, flag: .open(isOpen))
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
                    // The couple chat has no subject id, so the key is left out.
                    args: [
                        "p_couple_id": coupleID.uuidString.lowercased(),
                        "p_subject_kind": subject.kind.rawValue,
                    ].merging(subject.serverID.map { ["p_subject_id": $0.uuidString.lowercased()] } ?? [:]) { $1 },
                    as: PresenceRow.self
                )
                var latest = ThreadChatPresence.none
                for await result in results {
                    switch result {
                    case let .value(row):
                        latest = row.presence
                    case .failure:
                        // While the subscription is down, nobody can say the partner
                        // is still in the chat. Keep the read mark.
                        latest.partnerIsTyping = false
                        latest.partnerIsInChat = false
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
        guard let target = item.reactionTarget else { throw ThreadChatServiceError.unavailable }
        try await LiveReactionGateway(client: client).setReaction(emoji, on: target)
    }
}
