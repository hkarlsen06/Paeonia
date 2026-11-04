import Foundation

nonisolated struct ConversationThreadRow: Decodable {
    let threadID: UUID
    let coupleID: UUID
    let kind: String
    let dailyQuestionID: UUID?
    let memoryID: UUID?
    let storyID: UUID?
    var gameKind: GameKind?
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
    let viewerReadThroughMessageID: UUID?
    let topicKey: String?
    let privateTopic: Bool?

    /// What the chat is about, from the id that matches its kind.
    private var subject: ThreadChatSubject? {
        switch kind {
        case "daily_question": dailyQuestionID.map(ThreadChatSubject.question)
        case "memory": memoryID.map(ThreadChatSubject.memory)
        case "story": storyID.map(ThreadChatSubject.story)
        case "game": gameKind.map { .game(GameChatSubject(coupleID: coupleID, kind: $0)) }
        case "couple": .couple
        default: nil
        }
    }

    /// The summary of a chat that is shown. Nil for a deleted or hidden thread, such as the
    /// replies to a story that was deleted.
    var summary: ThreadChatSummary? {
        guard deletedAt == nil, moderationStatus == "visible", let subject else { return nil }
        let previewIsVisible = lastMessageDeletedAt == nil
            && lastMessageModerationStatus == "visible"
        return ThreadChatSummary(
            threadID: threadID,
            coupleID: coupleID,
            subject: subject,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageID: previewIsVisible ? lastMessageID : nil,
            lastMessageAt: previewIsVisible ? lastMessageAt : nil,
            lastMessageSenderUserID: previewIsVisible ? lastMessageSenderUserID : nil,
            lastMessageBody: previewIsVisible ? lastMessageBody : nil,
            lastMessageMediaType: previewIsVisible ? lastMessageMediaType : nil,
            viewerReadThroughAt: viewerReadThroughAt,
            viewerReadThroughMessageID: viewerReadThroughMessageID,
            topicKey: topicKey,
            isPrivateTopic: privateTopic
        )
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case coupleID = "couple_id"
        case kind
        case dailyQuestionID = "daily_question_id"
        case memoryID = "memory_id"
        case storyID = "story_id"
        case gameKind = "game_kind"
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
        case viewerReadThroughMessageID = "viewer_read_through_message_id"
        case topicKey = "topic_key"
        case privateTopic = "private_topic"
    }
}

nonisolated struct ThreadMessageRow: Decodable {
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
    let replyToAnswerID: UUID?
    var replyToGameResultSource: GameConversationSource?
    let reactions: [EmojiReaction]

    nonisolated struct MediaRow: Decodable {
        let mediaAssetID: UUID
        let mediaType: String
        let width: Int?
        let height: Int?
        let durationMs: Int?
        var accessibilityText: String?

        var voice: ThreadChatVoice {
            ThreadChatVoice(mediaAssetID: mediaAssetID, durationMs: durationMs, transcript: accessibilityText)
        }

        var photo: ThreadChatPhoto {
            ThreadChatPhoto(
                mediaAssetID: mediaAssetID, width: width, height: height, accessibilityText: accessibilityText
            )
        }

        enum CodingKeys: String, CodingKey {
            case mediaAssetID = "media_asset_id"
            case mediaType = "media_type"
            case width
            case height
            case durationMs = "duration_ms"
            case accessibilityText = "accessibility_text"
        }
    }

    func message(subjectID: UUID) -> ThreadChatMessage? {
        guard moderationStatus == "visible" else { return nil }
        // A message its sender took back stays as a bare marker. The server sends no text,
        // files or reactions with it.
        if let deletedAt {
            return ThreadChatMessage(
                id: messageID,
                threadID: threadID,
                subjectID: subjectID,
                senderUserID: senderUserID,
                body: "",
                createdAt: createdAt,
                clientOperationID: nil,
                isSending: false,
                deletedAt: deletedAt
            )
        }
        // A server without media details only ever had voice messages in these chats.
        let media = media ?? (mediaAssetIDs ?? []).map {
            MediaRow(mediaAssetID: $0, mediaType: "voice", width: nil, height: nil, durationMs: nil)
        }
        let voice = media.first { $0.mediaType == "voice" }?.voice
        let photos = media.filter { $0.mediaType == "image" }.map(\.photo)
        guard body != nil || voice != nil || !photos.isEmpty else { return nil }
        return ThreadChatMessage(
            id: messageID,
            threadID: threadID,
            subjectID: subjectID,
            senderUserID: senderUserID,
            body: body ?? "",
            createdAt: createdAt,
            clientOperationID: nil,
            isSending: false,
            voice: voice,
            photos: photos.isEmpty ? nil : photos,
            replyTo: replyToGameResultSource.map(ThreadChatItemID.gameResult)
                ?? ThreadChatItemID(messageID: replyToMessageID, answerID: replyToAnswerID),
            editedAt: editedAt,
            reactions: reactions
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
        case replyToAnswerID = "reply_to_answer_id"
        case replyToGameResultSource = "reply_to_game_result_source"
        case reactions
    }
}

nonisolated struct ThreadMessagesPageRow: Decodable {
    let messages: [ThreadMessageRow]
    let hasMore: Bool

    func page(subjectID: UUID) -> ThreadChatMessagePage {
        ThreadChatMessagePage(
            messages: messages.compactMap { $0.message(subjectID: subjectID) },
            hasMore: hasMore,
            oldestAt: messages.first?.createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}

nonisolated struct PresenceRow: Decodable {
    let partnerTyping: Bool
    let partnerLastReadMessageID: UUID?

    var presence: ThreadChatPresence {
        ThreadChatPresence(partnerIsTyping: partnerTyping, partnerLastReadMessageID: partnerLastReadMessageID)
    }

    enum CodingKeys: String, CodingKey {
        case partnerTyping = "partner_typing"
        case partnerLastReadMessageID = "partner_last_read_message_id"
    }
}
