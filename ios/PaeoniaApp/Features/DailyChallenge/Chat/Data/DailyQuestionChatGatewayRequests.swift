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
