import Foundation

nonisolated struct ConversationThreadRow: Decodable {
    let threadID: UUID
    let coupleID: UUID
    let kind: String
    let dailyQuestionID: UUID?
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
    let topicKey: String?
    let privateTopic: Bool?

    var dailyQuestionSummary: DailyQuestionThreadSummary? {
        guard kind == "daily_question", deletedAt == nil, moderationStatus == "visible",
              let dailyQuestionID else { return nil }
        let previewIsVisible = lastMessageDeletedAt == nil
            && lastMessageModerationStatus == "visible"
        return DailyQuestionThreadSummary(
            threadID: threadID,
            coupleID: coupleID,
            questionID: dailyQuestionID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageID: previewIsVisible ? lastMessageID : nil,
            lastMessageAt: previewIsVisible ? lastMessageAt : nil,
            lastMessageSenderUserID: previewIsVisible ? lastMessageSenderUserID : nil,
            lastMessageBody: previewIsVisible ? lastMessageBody : nil,
            lastMessageMediaType: previewIsVisible ? lastMessageMediaType : nil,
            viewerReadThroughAt: viewerReadThroughAt,
            topicKey: topicKey,
            isPrivateTopic: privateTopic
        )
    }

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case coupleID = "couple_id"
        case kind
        case dailyQuestionID = "daily_question_id"
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

    func message(questionID: UUID) -> DailyQuestionChatMessage? {
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
            questionID: questionID,
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

nonisolated struct ThreadMessagesPageRow: Decodable {
    let messages: [ThreadMessageRow]
    let hasMore: Bool

    func page(questionID: UUID) -> DailyQuestionChatMessagePage {
        DailyQuestionChatMessagePage(
            messages: messages.compactMap { $0.message(questionID: questionID) },
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

    var presence: DailyChatPresence {
        DailyChatPresence(partnerIsTyping: partnerTyping, partnerLastReadMessageID: partnerLastReadMessageID)
    }

    enum CodingKeys: String, CodingKey {
        case partnerTyping = "partner_typing"
        case partnerLastReadMessageID = "partner_last_read_message_id"
    }
}
