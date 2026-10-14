import ExyteChat
import Foundation

/// Where a bubble sits in a run of messages from the same person, which decides its
/// corner shape and whether the avatar shows. Ported from Tidex's chat grouping.
enum DailyChatGroupPosition: Hashable {
    case standalone
    case leading
    case middle
    case trailing
}

struct DailyChatGroupContext: Hashable {
    let position: DailyChatGroupPosition
    let isCurrentUser: Bool

    static func standalone(isCurrentUser: Bool) -> Self {
        Self(position: .standalone, isCurrentUser: isCurrentUser)
    }

    var joinsPrevious: Bool {
        position == .middle || position == .trailing
    }

    var joinsNext: Bool {
        position == .leading || position == .middle
    }

    var showsAvatar: Bool {
        !isCurrentUser && !joinsPrevious
    }

    /// The same run, continued by one more bubble after this one.
    func joiningNext() -> Self {
        let next: DailyChatGroupPosition = switch position {
        case .standalone: .leading
        case .trailing: .middle
        case .leading, .middle: position
        }
        return Self(position: next, isCurrentUser: isCurrentUser)
    }
}

enum DailyChatGrouping {
    /// Messages further apart than this start a new run.
    static let maximumGap: TimeInterval = 5 * 60

    static func context(
        for message: DailyQuestionChatMessage,
        previous: DailyQuestionChatMessage?,
        next: DailyQuestionChatMessage?,
        currentUserID: UUID?
    ) -> DailyChatGroupContext {
        let joinsPrevious = previous.map { shouldGroup($0, message) } ?? false
        let joinsNext = next.map { shouldGroup(message, $0) } ?? false
        let position: DailyChatGroupPosition = switch (joinsPrevious, joinsNext) {
        case (false, false): .standalone
        case (false, true): .leading
        case (true, true): .middle
        case (true, false): .trailing
        }
        return DailyChatGroupContext(position: position, isCurrentUser: message.senderUserID == currentUserID)
    }

    /// Plain text from the same person close together joins one run. A reply or a
    /// voice message always stands on its own, like a photo does in Tidex.
    static func shouldGroup(_ lhs: DailyQuestionChatMessage, _ rhs: DailyQuestionChatMessage) -> Bool {
        guard lhs.senderUserID == rhs.senderUserID else { return false }
        guard !lhs.hasMedia, !rhs.hasMedia, lhs.replyToMessageID == nil, rhs.replyToMessageID == nil else {
            return false
        }
        let gap = rhs.createdAt.timeIntervalSince(lhs.createdAt)
        return gap >= 0 && gap <= maximumGap
    }
}

/// The quoted message shown above a reply, and in the composer while writing one.
struct DailyChatReplyPreview: Hashable {
    let messageID: UUID
    let senderName: String
    /// Nil when the quoted message is no longer in the chat.
    let snippet: String?
    let isVoice: Bool
    /// The quoted message's photos, shown as small thumbnails.
    var photos: [DailyQuestionChatPhoto] = []
}

/// The small line under your own messages. Like Tidex: Sending and Not sent show on
/// every message in that state, Read on the newest one the partner has read, and
/// Sent on your newest message.
enum DailyChatMessageStatus: Hashable {
    case sending
    case sent
    case read
    case failed
}

/// One row of the chat list, worked out once per change instead of in every cell.
struct DailyChatRow {
    enum Kind {
        case question(String)
        case answer(DailyQuestionAnswerDetail)
        case message(DailyQuestionChatMessage)
        /// The partner's typing dots, after the newest message.
        case typing
    }

    let id: String
    let kind: Kind
    let isCurrentUser: Bool
    let createdAt: Date
    let groupContext: DailyChatGroupContext
    let status: DailyChatMessageStatus?
    let quotedPreview: DailyChatReplyPreview?

    var message: DailyQuestionChatMessage? {
        if case let .message(message) = kind { return message }
        return nil
    }

    var isAnswer: Bool {
        if case .answer = kind { return true }
        return false
    }
}

/// The chat list worked out from the page's data: ExyteChat's messages and the row
/// models the cells draw from. Built in one pass and cached until the data changes,
/// so scrolling and unrelated redraws never redo it. Ported from Tidex's chat projection.
struct DailyChatProjection {
    struct Input: Equatable {
        let prompt: String
        let questionStartsAt: Date
        let answers: [DailyQuestionAnswerDetail]
        let messages: [DailyQuestionChatMessage]
        let currentUserID: UUID?
        let partnerName: String
        let youName: String
        var partnerIsTyping = false
        var partnerLastReadMessageID: UUID?
        /// The partner has opened the page since the user's answer showed for them.
        var ownAnswerSeenByPartner = false
    }

    static let questionRowID = "question"
    static let answerRowPrefix = "answer-"
    static let typingRowID = "typing-indicator"

    let exyteMessages: [ExyteChat.Message]
    let rowsByID: [String: DailyChatRow]

    static let empty = DailyChatProjection(exyteMessages: [], rowsByID: [:])

    /// A message keeps its row id when the server confirms it.
    static func rowID(for message: DailyQuestionChatMessage) -> String {
        (message.clientOperationID ?? message.id).uuidString
    }

    static func make(input: Input) -> DailyChatProjection {
        var exyteMessages: [ExyteChat.Message] = []
        var rowsByID: [String: DailyChatRow] = [:]
        exyteMessages.reserveCapacity(input.messages.count + 3)
        rowsByID.reserveCapacity(input.messages.count + 3)

        func user(_ userID: UUID?, isCurrentUser: Bool) -> ExyteChat.User {
            ExyteChat.User(
                id: userID?.uuidString ?? questionRowID,
                name: isCurrentUser ? input.youName : input.partnerName,
                avatarURL: nil,
                isCurrentUser: isCurrentUser
            )
        }

        /// `text` and `status` are never drawn by ExyteChat. The long-press menu reads
        /// them to pick its actions, since it only gets ExyteChat's message.
        func append(
            _ row: DailyChatRow,
            user: ExyteChat.User,
            redrawKey: some Hashable,
            text: String = "",
            status: ExyteChat.Message.Status? = nil
        ) {
            var message = ExyteChat.Message(
                id: row.id,
                user: user,
                status: status,
                createdAt: row.createdAt,
                text: text
            )
            message.triggerRedraw = redrawToken(of: redrawKey)
            exyteMessages.append(message)
            rowsByID[row.id] = row
        }

        // Paeonia's question opens the chat, then the answers, then the messages. An
        // answer edited after the chat started still sorts above the first message.
        let firstMessageAt = input.messages.first?.createdAt ?? .distantFuture
        let firstAnswerAt = input.answers.first.map { min($0.answeredAt, firstMessageAt) } ?? firstMessageAt
        let questionRow = DailyChatRow(
            id: questionRowID,
            kind: .question(input.prompt),
            isCurrentUser: false,
            createdAt: min(input.questionStartsAt, firstAnswerAt),
            groupContext: .standalone(isCurrentUser: false),
            status: nil,
            quotedPreview: nil
        )
        append(questionRow, user: user(nil, isCurrentUser: false), redrawKey: input.prompt, text: input.prompt)

        let lastSentOwnMessageID = input.messages.last {
            $0.senderUserID == input.currentUserID && !$0.isSending && !$0.sendFailed
        }?.id
        // Read shows on your answer until you send a message, which then carries it.
        let answerStatus: DailyChatMessageStatus? =
            input.ownAnswerSeenByPartner && lastSentOwnMessageID == nil ? .read : nil

        for answer in input.answers {
            let row = DailyChatRow(
                id: answerRowPrefix + answer.answerID.uuidString,
                kind: .answer(answer),
                isCurrentUser: answer.isOwnAnswer,
                createdAt: min(answer.answeredAt, firstMessageAt),
                groupContext: .standalone(isCurrentUser: answer.isOwnAnswer),
                status: answer.isOwnAnswer ? answerStatus : nil,
                quotedPreview: nil
            )
            append(
                row,
                user: user(answer.answerUserID, isCurrentUser: answer.isOwnAnswer),
                redrawKey: AnswerRedrawKey(answer: answer, status: row.status),
                text: answer.textBody ?? ""
            )
        }

        let messagesByID = Dictionary(input.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let readReceiptMessageID = readReceiptMessageID(input: input, messagesByID: messagesByID)
        // The dots join the partner's newest message when it is the last one, like Tidex.
        let typingJoinsPrevious = input.partnerIsTyping
            && input.messages.last.map { $0.senderUserID != input.currentUserID && !$0.hasMedia } == true

        for (index, message) in input.messages.enumerated() {
            let isCurrentUser = message.senderUserID == input.currentUserID
            var groupContext = DailyChatGrouping.context(
                for: message,
                previous: index > 0 ? input.messages[index - 1] : nil,
                next: index + 1 < input.messages.count ? input.messages[index + 1] : nil,
                currentUserID: input.currentUserID
            )
            if typingJoinsPrevious, index == input.messages.count - 1 {
                groupContext = groupContext.joiningNext()
            }
            let status: DailyChatMessageStatus? = if message.sendFailed {
                .failed
            } else if message.isSending {
                .sending
            } else if message.id == readReceiptMessageID {
                .read
            } else if message.id == lastSentOwnMessageID {
                .sent
            } else {
                nil
            }
            let quotedPreview = message.replyToMessageID.map { replyID in
                preview(of: messagesByID[replyID], id: replyID, input: input)
            }
            let row = DailyChatRow(
                id: rowID(for: message),
                kind: .message(message),
                isCurrentUser: isCurrentUser,
                createdAt: message.createdAt,
                groupContext: groupContext,
                status: status,
                quotedPreview: quotedPreview
            )
            append(
                row,
                user: user(message.senderUserID, isCurrentUser: isCurrentUser),
                redrawKey: MessageRedrawKey(
                    message: message,
                    groupContext: groupContext,
                    status: status,
                    quotedPreview: quotedPreview
                ),
                text: message.voice == nil ? message.body : "",
                status: message.isSending || message.sendFailed ? .sending : .sent
            )
        }

        if input.partnerIsTyping {
            // Dated like the newest row, so the dots stay in its day and at the bottom.
            let row = DailyChatRow(
                id: typingRowID,
                kind: .typing,
                isCurrentUser: false,
                createdAt: exyteMessages.last?.createdAt ?? .now,
                groupContext: DailyChatGroupContext(
                    position: typingJoinsPrevious ? .trailing : .standalone,
                    isCurrentUser: false
                ),
                status: nil,
                quotedPreview: nil
            )
            append(row, user: user(nil, isCurrentUser: false), redrawKey: typingJoinsPrevious)
        }
        return DailyChatProjection(exyteMessages: exyteMessages, rowsByID: rowsByID)
    }

    /// Your newest message the partner has read through. The partner's mark is a
    /// message id, so read means sent at or before that message.
    private static func readReceiptMessageID(
        input: Input,
        messagesByID: [UUID: DailyQuestionChatMessage]
    ) -> UUID? {
        guard let readID = input.partnerLastReadMessageID, let readThrough = messagesByID[readID] else { return nil }
        return input.messages.last { message in
            message.senderUserID == input.currentUserID
                && !message.isSending
                && !message.sendFailed
                && (message.createdAt, message.id.uuidString) <= (readThrough.createdAt, readThrough.id.uuidString)
        }?.id
    }

    static func preview(
        of message: DailyQuestionChatMessage?,
        id: UUID,
        input: Input
    ) -> DailyChatReplyPreview {
        let isOwn = message?.senderUserID == input.currentUserID
        return DailyChatReplyPreview(
            messageID: id,
            senderName: message == nil ? input.partnerName : (isOwn ? input.youName : input.partnerName),
            snippet: message.map { $0.voice == nil ? $0.body : "" },
            isVoice: message?.voice != nil,
            photos: message?.photos ?? []
        )
    }

    /// Everything a message row draws that ExyteChat's message doesn't carry. ExyteChat
    /// only redraws a row whose message changed, so this goes into `triggerRedraw`.
    private struct AnswerRedrawKey: Hashable {
        let answer: DailyQuestionAnswerDetail
        let status: DailyChatMessageStatus?
    }

    private struct MessageRedrawKey: Hashable {
        let body: String
        let isSending: Bool
        let sendFailed: Bool
        let voiceAssetID: UUID?
        let hasLocalVoice: Bool
        let photoAssetIDs: [UUID?]
        let hasLocalPhotos: Bool
        let isEdited: Bool
        let groupContext: DailyChatGroupContext
        let status: DailyChatMessageStatus?
        let quotedPreview: DailyChatReplyPreview?

        init(
            message: DailyQuestionChatMessage,
            groupContext: DailyChatGroupContext,
            status: DailyChatMessageStatus?,
            quotedPreview: DailyChatReplyPreview?
        ) {
            body = message.body
            isSending = message.isSending
            sendFailed = message.sendFailed
            voiceAssetID = message.voice?.mediaAssetID
            hasLocalVoice = message.voice?.data != nil
            photoAssetIDs = (message.photos ?? []).map(\.mediaAssetID)
            hasLocalPhotos = (message.photos ?? []).contains { $0.data != nil }
            isEdited = message.editedAt != nil
            self.groupContext = groupContext
            self.status = status
            self.quotedPreview = quotedPreview
        }
    }

    /// A UUID that changes whenever `value` changes. Hashes are seeded per launch, so
    /// tokens only compare within one run, which is all a redraw needs.
    static func redrawToken(of value: some Hashable) -> UUID {
        var hasher = Hasher()
        hasher.combine(value)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: hash >> (UInt64(index) * 8))
        }
        return NSUUID(uuidBytes: bytes) as UUID
    }

    /// Marks one row as highlighted, for example after tapping a quote jumps to it.
    /// Only that row's message changes, so only it redraws.
    func highlighting(_ rowID: String?) -> [ExyteChat.Message] {
        guard let rowID else { return exyteMessages }
        return exyteMessages.map { message in
            guard message.id == rowID else { return message }
            var highlighted = message
            highlighted.triggerRedraw = Self.redrawToken(of: [message.triggerRedraw?.uuidString, "highlight"])
            return highlighted
        }
    }
}

/// Keeps the last projection and rebuilds it only when its input changed.
@MainActor
final class DailyChatProjectionStore {
    private var cachedInput: DailyChatProjection.Input?
    private var cachedProjection = DailyChatProjection.empty

    func projection(for input: DailyChatProjection.Input) -> DailyChatProjection {
        guard cachedInput != input else { return cachedProjection }
        cachedInput = input
        cachedProjection = DailyChatProjection.make(input: input)
        return cachedProjection
    }
}
