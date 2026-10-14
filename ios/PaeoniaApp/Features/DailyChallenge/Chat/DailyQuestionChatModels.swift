import Foundation

nonisolated struct DailyQuestionThreadSummary: Codable, Equatable, Sendable {
    let threadID: UUID
    let coupleID: UUID
    let instanceID: UUID
    let createdAt: Date
    let updatedAt: Date
    let lastMessageID: UUID?
    let lastMessageAt: Date?
    let lastMessageSenderUserID: UUID?
    let lastMessageBody: String?
    /// The media type of the newest message's first attachment ("image" or "voice").
    var lastMessageMediaType: String?
    /// How far this user has read the chat on any of their devices, from the server.
    var viewerReadThroughAt: Date?

    /// What to show for the newest message. A shown message with no text has an
    /// attachment, because the server only leaves out the text of hidden messages.
    var lastMessagePreview: String? {
        if let body = lastMessageBody?.trimmedNonEmpty { return body }
        guard lastMessageID != nil else { return nil }
        return String(localized: lastMessageMediaType == "image" ? .dailyChatPhotoPreview : .dailyChatVoicePreview)
    }

    /// The newest message came from the partner after the user last read the chat:
    /// `readThrough` on this phone, or `viewerReadThroughAt` on any of their devices.
    func isUnread(by userID: UUID, readThrough: Date?) -> Bool {
        guard let lastMessageAt, let sender = lastMessageSenderUserID, sender != userID else { return false }
        guard let readThrough = [readThrough, viewerReadThroughAt].compactMap(\.self).max() else { return true }
        return lastMessageAt > readThrough
    }
}

nonisolated struct DailyQuestionChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let threadID: UUID?
    let instanceID: UUID
    let senderUserID: UUID
    let body: String
    let createdAt: Date
    let clientOperationID: UUID?
    let isSending: Bool
    /// A try to send it failed, so it may stay on this phone a while.
    var isHeldOnPhone = false
    var sendFailed = false
    /// Set when the message is a voice message instead of text.
    var voice: DailyQuestionChatVoice?
    /// Photos in the message, in order. The text, if any, is their caption. Optional, so
    /// messages cached before photos existed still decode.
    var photos: [DailyQuestionChatPhoto]?
    /// The earlier message in the thread this one answers.
    var replyToMessageID: UUID?
    /// When the sender last changed the text.
    var editedAt: Date?

    /// How long after sending the sender can change a message. The server checks it too.
    static let editWindow: TimeInterval = 5 * 60

    /// The user's own sent message with text, still inside the edit window. A voice
    /// message has no text to change. A question's answers are not chat messages, so
    /// they never get here.
    func canEdit(by userID: UUID?, now: Date = .now) -> Bool {
        senderUserID == userID && !isSending && !sendFailed && threadID != nil && voice == nil
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && now.timeIntervalSince(createdAt) <= Self.editWindow
    }

    static func visibleOrdered(
        remote: [DailyQuestionChatMessage],
        optimistic: [DailyQuestionChatMessage]
    ) -> [DailyQuestionChatMessage] {
        var messagesByID = Dictionary(
            remote.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for message in optimistic where message.isSending || message.sendFailed {
            if let operationID = message.clientOperationID,
               messagesByID.values.contains(where: { $0.clientOperationID == operationID }) {
                continue
            }
            messagesByID[message.id] = message
        }

        return messagesByID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// One-shot reads of a thread can be older than live results that landed while
    /// the request was in flight. The cache holds those newer messages, so a save of
    /// the read keeps every confirmed cached message that the read lacks and that
    /// is newer than the read's newest message. Older ones stay dropped, so a message
    /// the server removed disappears.
    static func keepingNewerCached(
        _ snapshot: [DailyQuestionChatMessage],
        cached: [DailyQuestionChatMessage]
    ) -> [DailyQuestionChatMessage] {
        let newest = snapshot.map(\.createdAt).max() ?? .distantPast
        let snapshotIDs = Set(snapshot.map(\.id))
        return snapshot + cached.filter {
            !$0.isSending && !$0.sendFailed && !snapshotIDs.contains($0.id) && $0.createdAt > newest
        }
    }

    /// Links live server copies of this device's still-sending messages to their
    /// operations. The live query can deliver a message before the send's own
    /// response confirms it, and the server copy carries no client operation id,
    /// so `visibleOrdered` would show it twice.
    ///
    /// A server message that already has an operation id in `cached` keeps it, so
    /// the next live result before the send's response does not drop the link. A
    /// server message that the cache has not seen yet is matched to the oldest
    /// sending message with the same sender and text, and takes over that message's
    /// operation id. A message with the same text sent earlier is already in
    /// `cached` and never matches again.
    static func claimingPending(
        remote: [DailyQuestionChatMessage],
        cached: [DailyQuestionChatMessage],
        pending: [DailyQuestionChatMessage]
    ) -> [DailyQuestionChatMessage] {
        let confirmed = cached.filter { !$0.isSending && !$0.sendFailed }
        let claimedOperations = Dictionary(
            confirmed.compactMap { message in message.clientOperationID.map { (message.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let claimedOperationIDs = Set(claimedOperations.values)
        var waiting = pending
            .filter { message in
                guard message.isSending, let operationID = message.clientOperationID else { return false }
                return !claimedOperationIDs.contains(operationID)
            }
            .sorted { $0.createdAt < $1.createdAt }
        guard !waiting.isEmpty || !claimedOperations.isEmpty else { return remote }

        let knownIDs = Set(confirmed.map(\.id))
        return remote.sorted { $0.createdAt < $1.createdAt }.map { message in
            guard message.clientOperationID == nil else { return message }
            if let operationID = claimedOperations[message.id] {
                return message.confirmed(by: operationID)
            }
            guard !knownIDs.contains(message.id),
                  let index = waiting.firstIndex(where: { $0.isSameSend(as: message) })
            else { return message }
            return message.confirmed(by: waiting.remove(at: index).clientOperationID)
        }
    }

    /// A voice message gets its id on this phone, so the server copy has the same id.
    /// Two texts can only be matched by what they say.
    private func isSameSend(as remote: DailyQuestionChatMessage) -> Bool {
        guard senderUserID == remote.senderUserID else { return false }
        if hasMedia || remote.hasMedia { return id == remote.id }
        return body == remote.body
    }

    private func confirmed(by operationID: UUID?) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: id,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: operationID,
            isSending: false,
            voice: voice,
            photos: photos,
            replyToMessageID: replyToMessageID,
            editedAt: editedAt
        )
    }

    var hasMedia: Bool {
        voice != nil || !(photos ?? []).isEmpty
    }
}

/// One photo in a chat message.
nonisolated struct DailyQuestionChatPhoto: Codable, Equatable, Hashable, Sendable {
    /// The uploaded photo. Nil until the message is sent.
    var mediaAssetID: UUID?
    /// The compressed photo on this phone while it sends, or after it failed.
    var data: Data?
    var width: Int?
    var height: Int?
}

/// The photos of a queued message, already compressed. Every photo is reserved under
/// the message's id, and the upload operations are fixed so a retry reuses them.
nonisolated struct DailyQuestionChatPhotosPayload: Codable, Equatable, Sendable {
    nonisolated struct Item: Codable, Equatable, Sendable {
        let data: Data
        let width: Int
        let height: Int
        let reserveOperation: SyncClientOperation
        let finalizeOperation: SyncClientOperation
    }

    let messageID: UUID
    let items: [Item]

    var pendingPhotos: [DailyQuestionChatPhoto] {
        items.map { DailyQuestionChatPhoto(data: $0.data, width: $0.width, height: $0.height) }
    }
}

/// The recording in a voice message.
nonisolated struct DailyQuestionChatVoice: Codable, Equatable, Sendable {
    /// The uploaded recording. Nil until the message is sent.
    var mediaAssetID: UUID?
    /// The recording on this phone while it sends, or after it failed, so it plays
    /// without a download and can be sent again.
    var data: Data?
    var durationMs: Int?
}

/// A queued voice message. The upload operations are fixed here, so a retry never
/// uploads the recording twice.
nonisolated struct DailyQuestionChatVoicePayload: Codable, Equatable, Sendable {
    /// The upload is reserved under this id, and the server gives the message the same id.
    let messageID: UUID
    let data: Data
    let durationMs: Int
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation

    var pendingVoice: DailyQuestionChatVoice {
        DailyQuestionChatVoice(data: data, durationMs: durationMs)
    }
}

extension DailyChallengeQuestion {
    nonisolated var isChatAvailable: Bool {
        hasOwnAnswer && hasPartnerAnswer && canViewPartnerAnswer
    }
}

nonisolated struct CreateDailyQuestionThreadMessageOperationPayload: Codable, Equatable, Sendable {
    let instanceID: UUID
    let coupleID: UUID
    let body: String
    var voice: DailyQuestionChatVoicePayload?
    var photos: DailyQuestionChatPhotosPayload?
}

nonisolated struct SendDailyQuestionThreadMessageOperationPayload: Codable, Equatable, Sendable {
    let instanceID: UUID
    let coupleID: UUID
    let threadID: UUID?
    let body: String
    var voice: DailyQuestionChatVoicePayload?
    var photos: DailyQuestionChatPhotosPayload?
    var replyToMessageID: UUID?
}

nonisolated struct DailyQuestionThreadMessageResponse: Decodable, Equatable, Sendable {
    let threadID: UUID
    let messageID: UUID

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case messageID = "message_id"
    }
}
