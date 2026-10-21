import Foundation

nonisolated struct ThreadChatSummary: Codable, Equatable, Sendable {
    let threadID: UUID
    let coupleID: UUID
    /// What the chat is about: a question, a memory or a story. A couple has one chat for each.
    let subject: ThreadChatSubject
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
    /// The topic of a topic question's chat, nil for a daily question.
    var topicKey: String?
    /// The chat belongs to a private topic (Flirt), so nothing about it shows outside it.
    var isPrivateTopic: Bool?

    /// The question the chat is about, nil for a memory's or a story's chat.
    var questionID: UUID? {
        subject.kind == .question ? subject.id : nil
    }

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

/// One read of a thread's messages, oldest first. The newest page follows the chat live,
/// and older pages load when the person scrolls up.
nonisolated struct ThreadChatMessagePage: Equatable, Sendable {
    /// The messages the chat shows. The server also sends removed ones, which are left out.
    var messages: [ThreadChatMessage]
    /// Older messages exist on the server.
    var hasMore: Bool
    /// When the oldest message in the read was written, removed ones included.
    var oldestAt: Date?
}

/// The oldest message the phone has. The next page of older messages comes before it.
nonisolated struct ThreadChatMessageCursor: Equatable, Sendable {
    let createdAt: Date
    let messageID: UUID
}

nonisolated struct ThreadChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let threadID: UUID?
    /// The question whose chat the message belongs to.
    let subjectID: UUID
    let senderUserID: UUID
    let body: String
    let createdAt: Date
    let clientOperationID: UUID?
    let isSending: Bool
    /// A try to send it failed, so it may stay on this phone a while.
    var isHeldOnPhone = false
    var sendFailed = false
    /// Set when the message is a voice message instead of text.
    var voice: ThreadChatVoice?
    /// Photos in the message, in order. The text, if any, is their caption. Optional, so
    /// messages cached before photos existed still decode.
    var photos: [ThreadChatPhoto]?
    /// The earlier message or the answer this one replies to.
    var replyTo: ThreadChatItemID?
    /// When the sender last changed the text.
    var editedAt: Date?
    /// Who reacted with what, as the server last sent it.
    var reactions: [EmojiReaction] = []
    /// When the sender took the message back. The message then keeps only who sent it and
    /// when, so the chat can say it was deleted. A pending delete on this phone sets it
    /// too, before the server has heard.
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    /// How many messages one read of a thread asks for.
    static let pageSize = 50

    /// How long after sending the sender can change a message. The server checks it too.
    static let editWindow: TimeInterval = 5 * 60

    /// The user's own sent message with text, still inside the edit window. A voice
    /// message has no text to change. A question's answers are not chat messages, so
    /// they never get here.
    func canEdit(by userID: UUID?, now: Date = .now) -> Bool {
        senderUserID == userID && !isSending && !sendFailed && !isDeleted && threadID != nil && voice == nil
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && now.timeIntervalSince(createdAt) <= Self.editWindow
    }

    /// The user's own message that is on the server and still shown. They can take back
    /// text, photos and voice messages, with no time limit. A message that is still
    /// sending or failed is removed from this phone instead (`isUnsent`).
    func canDelete(by userID: UUID?) -> Bool {
        senderUserID == userID && !isDeleted && (isUnsent || threadID != nil)
    }

    /// Not on the server yet: it is waiting in the send queue, or it gave up.
    var isUnsent: Bool { isSending || sendFailed }

    /// What is left of a message once its sender took it back: who sent it and when.
    var takenBack: ThreadChatMessage {
        ThreadChatMessage(
            id: id,
            threadID: threadID,
            subjectID: subjectID,
            senderUserID: senderUserID,
            body: "",
            createdAt: createdAt,
            clientOperationID: clientOperationID,
            isSending: false,
            deletedAt: deletedAt ?? .now
        )
    }

    /// Shows the messages the user has taken back on this phone as deleted. The server may
    /// still send them as shown until it has heard, and they must not flash back.
    static func applyingDeletions(
        _ messages: [ThreadChatMessage],
        deletions: ThreadChatPendingDeletions
    ) -> [ThreadChatMessage] {
        guard !deletions.isEmpty else { return messages }
        return messages.map { message in
            guard !message.isDeleted, let deletedAt = deletions.deletedAt(of: message) else { return message }
            var gone = message.takenBack
            gone.deletedAt = deletedAt
            return gone
        }
    }

    /// The media files of the messages that `incoming` shows as deleted while `cached`
    /// still has them, which this phone no longer needs.
    static func mediaAssetIDsDeleted(
        in incoming: [ThreadChatMessage],
        comparedTo cached: [ThreadChatMessage]
    ) -> [UUID] {
        let deletedIDs = Set(incoming.filter(\.isDeleted).map(\.id))
        return cached.filter { !$0.isDeleted && deletedIDs.contains($0.id) }.flatMap(\.mediaAssetIDs)
    }

    /// The uploaded files of the message's photos or voice recording.
    var mediaAssetIDs: [UUID] {
        (photos ?? []).compactMap(\.mediaAssetID) + [voice?.mediaAssetID].compactMap(\.self)
    }

    static func visibleOrdered(
        remote: [ThreadChatMessage],
        optimistic: [ThreadChatMessage]
    ) -> [ThreadChatMessage] {
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
        _ snapshot: [ThreadChatMessage],
        cached: [ThreadChatMessage]
    ) -> [ThreadChatMessage] {
        let newest = snapshot.map(\.createdAt).max() ?? .distantPast
        let snapshotIDs = Set(snapshot.map(\.id))
        return snapshot + cached.filter {
            !$0.isSending && !$0.sendFailed && !snapshotIDs.contains($0.id) && $0.createdAt > newest
        }
    }

    /// A page of the thread replaces only the newest part of the cached chat. When older
    /// messages exist on the server, the confirmed cached ones from before the page's
    /// oldest message stay, because earlier loads of older pages put them there.
    /// They stay only when the page overlaps the cache. A page with no message in common
    /// means more than a page arrived since the cache was saved, and keeping the older
    /// messages would leave a hole that loading older messages never fills.
    static func keepingOlderCached(
        _ page: ThreadChatMessagePage,
        remote: [ThreadChatMessage],
        cached: [ThreadChatMessage]
    ) -> [ThreadChatMessage] {
        guard page.hasMore, let oldestAt = page.oldestAt else { return remote }
        let confirmed = cached.filter { !$0.isSending && !$0.sendFailed }
        let pageIDs = Set(page.messages.map(\.id))
        guard confirmed.contains(where: { pageIDs.contains($0.id) }) else { return remote }
        return remote + confirmed.filter { $0.createdAt < oldestAt }
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
        remote: [ThreadChatMessage],
        cached: [ThreadChatMessage],
        pending: [ThreadChatMessage]
    ) -> [ThreadChatMessage] {
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
    private func isSameSend(as remote: ThreadChatMessage) -> Bool {
        guard senderUserID == remote.senderUserID else { return false }
        if hasMedia || remote.hasMedia { return id == remote.id }
        return body == remote.body
    }

    private func confirmed(by operationID: UUID?) -> ThreadChatMessage {
        ThreadChatMessage(
            id: id,
            threadID: threadID,
            subjectID: subjectID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: operationID,
            isSending: false,
            voice: voice,
            photos: photos,
            replyTo: replyTo,
            editedAt: editedAt,
            reactions: reactions,
            deletedAt: deletedAt
        )
    }

    var hasMedia: Bool {
        voice != nil || !(photos ?? []).isEmpty
    }
}

/// A message in the chat or one of the answers on the page: what a reply points at, or
/// what a reaction is on. The server keeps them apart, for example as
/// `reply_to_message_id` and `reply_to_answer_id`.
nonisolated enum ThreadChatItemID: Codable, Hashable, Sendable {
    case message(UUID)
    case answer(UUID)

    var messageID: UUID? {
        if case let .message(id) = self { return id }
        return nil
    }

    var answerID: UUID? {
        if case let .answer(id) = self { return id }
        return nil
    }

    /// What the shared reactions call this message or answer.
    var reactionTarget: ReactionTarget {
        switch self {
        case let .message(id): .threadMessage(id)
        case let .answer(id): .dailyAnswer(id)
        }
    }

    init?(reactionTarget: ReactionTarget) {
        switch reactionTarget.kind {
        case .threadMessage: self = .message(reactionTarget.id)
        case .dailyAnswer: self = .answer(reactionTarget.id)
        default: return nil
        }
    }

    init?(messageID: UUID?, answerID: UUID?) {
        if let messageID {
            self = .message(messageID)
        } else if let answerID {
            self = .answer(answerID)
        } else {
            return nil
        }
    }
}

/// The message or answer the composer's next message replies to.
nonisolated enum ThreadChatReplyTarget: Equatable, Sendable {
    case message(ThreadChatMessage)
    case answer(DailyQuestionAnswerDetail)

    var id: ThreadChatItemID {
        switch self {
        case let .message(message): .message(message.id)
        case let .answer(answer): .answer(answer.answerID)
        }
    }
}

/// One photo in a chat message.
nonisolated struct ThreadChatPhoto: Codable, Equatable, Hashable, Sendable {
    /// The uploaded photo. Nil until the message is sent.
    var mediaAssetID: UUID?
    /// The compressed photo on this phone while it sends, or after it failed.
    var data: Data?
    var width: Int?
    var height: Int?
}

/// The photos of a queued message, already compressed. Every photo is reserved under
/// the message's id, and the upload operations are fixed so a retry reuses them.
nonisolated struct ThreadChatPhotosPayload: Codable, Equatable, Sendable {
    nonisolated struct Item: Codable, Equatable, Sendable {
        let data: Data
        let width: Int
        let height: Int
        let reserveOperation: SyncClientOperation
        let finalizeOperation: SyncClientOperation
    }

    let messageID: UUID
    let items: [Item]

    var pendingPhotos: [ThreadChatPhoto] {
        items.map { ThreadChatPhoto(data: $0.data, width: $0.width, height: $0.height) }
    }
}

/// The recording in a voice message.
nonisolated struct ThreadChatVoice: Codable, Equatable, Sendable {
    /// The uploaded recording. Nil until the message is sent.
    var mediaAssetID: UUID?
    /// The recording on this phone while it sends, or after it failed, so it plays
    /// without a download and can be sent again.
    var data: Data?
    var durationMs: Int?
}

/// A queued voice message. The upload operations are fixed here, so a retry never
/// uploads the recording twice.
nonisolated struct ThreadChatVoicePayload: Codable, Equatable, Sendable {
    /// The upload is reserved under this id, and the server gives the message the same id.
    let messageID: UUID
    let data: Data
    let durationMs: Int
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation

    var pendingVoice: ThreadChatVoice {
        ThreadChatVoice(data: data, durationMs: durationMs)
    }
}

/// A queued first message, which starts the chat of a question, a memory or a story.
nonisolated struct CreateChatThreadPayload: Codable, Equatable, Sendable {
    let subject: ThreadChatSubject
    let coupleID: UUID
    let body: String
    var voice: ThreadChatVoicePayload?
    var photos: ThreadChatPhotosPayload?
    /// The first message can reply to an answer. There are no messages to reply to yet.
    var replyToAnswerID: UUID?
}

nonisolated struct SendChatMessagePayload: Codable, Equatable, Sendable {
    let subject: ThreadChatSubject
    let coupleID: UUID
    let threadID: UUID?
    let body: String
    var voice: ThreadChatVoicePayload?
    var photos: ThreadChatPhotosPayload?
    var replyTo: ThreadChatItemID?
}

/// A queued delete of a message the user took back.
nonisolated struct DeleteChatMessagePayload: Codable, Equatable, Sendable {
    enum Target: Codable, Equatable, Sendable {
        /// A message the phone knows the server has.
        case message(UUID)
        /// A message whose send was tried and may have reached the server. The server gave it
        /// an id that this phone does not know until the send finishes, so the delete waits
        /// for that send.
        case sentBy(operationID: UUID)
    }

    let subjectID: UUID
    let target: Target
}

/// The messages the user took back whose delete the server has not confirmed, with the
/// time they were taken back.
nonisolated struct ThreadChatPendingDeletions: Equatable, Sendable {
    var byMessageID: [UUID: Date] = [:]
    /// Keyed by the client operation that sent the message.
    var bySendOperationID: [UUID: Date] = [:]

    var isEmpty: Bool { byMessageID.isEmpty && bySendOperationID.isEmpty }

    func deletedAt(of message: ThreadChatMessage) -> Date? {
        byMessageID[message.id] ?? message.clientOperationID.flatMap { bySendOperationID[$0] }
    }
}

nonisolated struct ThreadChatMessageResponse: Decodable, Equatable, Sendable {
    let threadID: UUID
    let messageID: UUID

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case messageID = "message_id"
    }
}
