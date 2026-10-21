import Foundation

nonisolated struct EditThreadMessageRequest: Encodable {
    let messageID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case body = "p_body"
    }
}

nonisolated struct TypingRequest: Encodable {
    let coupleID: UUID
    let questionID: UUID
    let isTyping: Bool
    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case questionID = "p_question_id"
        case isTyping = "p_is_typing"
    }
}

nonisolated struct MarkThreadReadRequest: Encodable {
    let threadID: UUID
    let messageID: UUID
    enum CodingKeys: String, CodingKey {
        case threadID = "p_thread_id"
        case messageID = "p_message_id"
    }
}

nonisolated struct MarkAnswerSeenRequest: Encodable {
    let instanceID: UUID
    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
    }
}

/// Sets a reaction on a message (`p_message_id`) or an answer (`p_answer_id`).
nonisolated struct ReactionRequest: Encodable {
    let item: DailyChatItemID
    /// Nil takes the reaction back.
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case answerID = "p_answer_id"
        case emoji = "p_emoji"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch item {
        case let .message(id): try container.encode(id, forKey: .messageID)
        case let .answer(id): try container.encode(id, forKey: .answerID)
        }
        // The server needs the key, with null to take the reaction back.
        try container.encode(emoji, forKey: .emoji)
    }
}

nonisolated struct QuestionChatRequest: Encodable {
    let coupleID: UUID
    let questionID: UUID
    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case questionID = "p_question_id"
    }
}

nonisolated struct ThreadMessagesRequest: Encodable {
    let threadID: UUID
    var limit = DailyQuestionChatMessage.pageSize
    /// Reads the page of messages before this one. Without it, the newest page.
    var before: DailyQuestionChatMessageCursor?

    enum CodingKeys: String, CodingKey {
        case threadID = "p_thread_id"
        case limit = "p_limit"
        case beforeCreatedAt = "p_before_created_at"
        case beforeMessageID = "p_before_message_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(limit, forKey: .limit)
        try container.encodeIfPresent(before?.createdAt, forKey: .beforeCreatedAt)
        try container.encodeIfPresent(before?.messageID, forKey: .beforeMessageID)
    }
}

nonisolated struct CreateThreadMessageRequest: Encodable {
    /// The couple the message was written in. The server refuses it if the user has since
    /// left that couple, instead of posting it to whichever couple they are in now.
    let coupleID: UUID
    let questionID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
    /// Left out of the request when nil.
    let replyToAnswerID: UUID?
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        payload: CreateDailyChatThreadPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) {
        coupleID = payload.coupleID
        questionID = payload.questionID
        body = payload.body
        self.mediaAssetIDs = mediaAssetIDs
        replyToAnswerID = payload.replyToAnswerID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case questionID = "p_question_id"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case replyToAnswerID = "p_reply_to_answer_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated struct SendThreadMessageRequest: Encodable {
    let threadID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
    /// What the message replies to. Each is left out of the request when nil.
    let replyToMessageID: UUID?
    let replyToAnswerID: UUID?
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyTo: DailyChatItemID?,
        operation: SyncClientOperation
    ) {
        self.threadID = threadID
        self.body = body
        self.mediaAssetIDs = mediaAssetIDs
        replyToMessageID = replyTo?.messageID
        replyToAnswerID = replyTo?.answerID
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
        case replyToAnswerID = "p_reply_to_answer_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
