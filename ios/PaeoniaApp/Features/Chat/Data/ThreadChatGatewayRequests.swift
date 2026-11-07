import Foundation

nonisolated struct EditThreadMessageRequest: Encodable {
    let messageID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
        case body = "p_body"
    }
}

nonisolated struct DeleteThreadMessageRequest: Encodable {
    let messageID: UUID
    let operation: ClientOperationFields

    enum CodingKeys: String, CodingKey {
        case messageID = "p_message_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageID, forKey: .messageID)
        try operation.encode(to: encoder)
    }
}

nonisolated struct TypingRequest: Encodable {
    let coupleID: UUID
    let subject: ThreadChatSubject
    let isTyping: Bool
    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case subjectKind = "p_subject_kind"
        case subjectID = "p_subject_id"
        case isTyping = "p_is_typing"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coupleID, forKey: .coupleID)
        try container.encode(subject.kind.rawValue, forKey: .subjectKind)
        if let subjectID = subject.serverID { try container.encode(subjectID, forKey: .subjectID) }
        try container.encode(isTyping, forKey: .isTyping)
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

nonisolated struct ThreadMessagesRequest: Encodable {
    let threadID: UUID
    var limit = ThreadChatMessage.pageSize
    /// Reads the page of messages before this one. Without it, the newest page.
    var before: ThreadChatMessageCursor?

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

/// Starts the chat of a question, a memory, a story, a game or the couple with its first message. Each kind has
/// its own server function (`ThreadChatSubject.Kind.createThreadFunction`) and names its
/// subject with its own argument.
nonisolated struct CreateThreadMessageRequest: Encodable {
    /// The couple the message was written in. The server refuses it if the user has since
    /// left that couple, instead of posting it to whichever couple they are in now. A memory
    /// and a story belong to one couple already, so their chats leave it out.
    let coupleID: UUID
    let subject: ThreadChatSubject
    let body: String
    let mediaAssetIDs: [UUID]
    /// Left out of the request when nil.
    let replyToAnswerID: UUID?
    let replyToGameResultSource: GameConversationSource?
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        payload: CreateChatThreadPayload,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) {
        coupleID = payload.coupleID
        subject = payload.subject
        body = payload.body
        self.mediaAssetIDs = mediaAssetIDs
        replyToAnswerID = payload.replyToAnswerID
        replyToGameResultSource = payload.replyToGameResultSource
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case questionID = "p_question_id"
        case memoryID = "p_memory_id"
        case storyID = "p_story_id"
        case gameKind = "p_game_kind"
        case body = "p_body"
        case mediaAssetIDs = "p_media_asset_ids"
        case replyToAnswerID = "p_reply_to_answer_id"
        case replyToGameResultSource = "p_reply_to_game_result_source"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch subject {
        case .question:
            try container.encode(coupleID, forKey: .coupleID)
            try container.encode(subject.id, forKey: .questionID)
            try container.encodeIfPresent(replyToAnswerID, forKey: .replyToAnswerID)
        case .memory:
            try container.encode(subject.id, forKey: .memoryID)
        case .story:
            try container.encode(subject.id, forKey: .storyID)
        case let .game(source):
            try container.encode(coupleID, forKey: .coupleID)
            try container.encode(source.kind, forKey: .gameKind)
            try container.encodeIfPresent(replyToGameResultSource, forKey: .replyToGameResultSource)
        case .couple:
            try container.encode(coupleID, forKey: .coupleID)
        }
        try container.encode(body, forKey: .body)
        try container.encode(mediaAssetIDs, forKey: .mediaAssetIDs)
        try container.encode(clientOperationID, forKey: .clientOperationID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(clientSequence, forKey: .clientSequence)
        try container.encode(localCreatedAt, forKey: .localCreatedAt)
    }
}

nonisolated struct SendThreadMessageRequest: Encodable {
    let threadID: UUID
    let body: String
    let mediaAssetIDs: [UUID]
    /// What the message replies to. Each is left out of the request when nil.
    let replyToMessageID: UUID?
    let replyToAnswerID: UUID?
    let replyToGameResultSource: GameConversationSource?
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        threadID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        replyTo: ThreadChatItemID?,
        operation: SyncClientOperation
    ) {
        self.threadID = threadID
        self.body = body
        self.mediaAssetIDs = mediaAssetIDs
        replyToMessageID = replyTo?.messageID
        replyToAnswerID = replyTo?.answerID
        replyToGameResultSource = replyTo?.gameResultSource
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
        case replyToGameResultSource = "p_reply_to_game_result_source"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
