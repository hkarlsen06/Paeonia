import ExyteChat
import Foundation

/// Where a bubble sits in a run of messages from the same person, which decides its
/// corner shape and whether the avatar shows. Ported from Tidex's chat grouping.
nonisolated enum ThreadChatGroupPosition: Hashable {
    case standalone
    case leading
    case middle
    case trailing
}

struct ThreadChatGroupContext: Hashable {
    let position: ThreadChatGroupPosition
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
        let next: ThreadChatGroupPosition = switch position {
        case .standalone: .leading
        case .trailing: .middle
        case .leading, .middle: position
        }
        return Self(position: next, isCurrentUser: isCurrentUser)
    }
}

enum ThreadChatGrouping {
    /// Messages further apart than this start a new run.
    static let maximumGap: TimeInterval = 5 * 60

    static func context(
        for message: ThreadChatMessage,
        previous: ThreadChatMessage?,
        next: ThreadChatMessage?,
        currentUserID: UUID?
    ) -> ThreadChatGroupContext {
        let joinsPrevious = previous.map { shouldGroup($0, message) } ?? false
        let joinsNext = next.map { shouldGroup(message, $0) } ?? false
        let position: ThreadChatGroupPosition = switch (joinsPrevious, joinsNext) {
        case (false, false): .standalone
        case (false, true): .leading
        case (true, true): .middle
        case (true, false): .trailing
        }
        return ThreadChatGroupContext(position: position, isCurrentUser: message.senderUserID == currentUserID)
    }

    /// Plain text from the same person close together joins one run. A reply or a
    /// voice message always stands on its own, like a photo does in Tidex.
    static func shouldGroup(_ lhs: ThreadChatMessage, _ rhs: ThreadChatMessage) -> Bool {
        guard lhs.senderUserID == rhs.senderUserID else { return false }
        guard !lhs.hasMedia, !rhs.hasMedia, lhs.replyTo == nil, rhs.replyTo == nil,
              !lhs.isDeleted, !rhs.isDeleted else {
            return false
        }
        let gap = rhs.createdAt.timeIntervalSince(lhs.createdAt)
        return gap >= 0 && gap <= maximumGap
    }
}

/// The quoted message or answer shown above a reply, and in the composer while writing one.
struct ThreadChatReplyPreview: Hashable {
    let target: ThreadChatItemID
    let senderName: String
    /// Nil when the quoted message or answer is no longer in the chat.
    let snippet: String?
    let isVoice: Bool
    /// The quoted message's photos, shown as small thumbnails.
    var photos: [ThreadChatPhoto] = []
    /// The sender took the quoted message back.
    var isDeleted = false

    var isAnswer: Bool { target.answerID != nil }
}

/// The small line under your own messages. Like Tidex: Sending and Not sent show on
/// every message in that state, Read on the newest one the partner has read, and
/// Sent on your newest message.
nonisolated enum ThreadChatMessageStatus: Hashable {
    case sending
    case sent
    case read
    case failed
}

/// One row of the chat list, worked out once per change instead of in every cell.
struct ThreadChatRow {
    enum Kind {
        case question(String)
        /// An answer, with the kind of media this day's question takes, since a question
        /// that comes back can take another kind.
        case answer(DailyQuestionAnswerDetail, mediaKind: DailyChallengeAnswerKind)
        /// How two partner-choice picks line up, above the day's answers.
        case partnerChoiceMatch(PartnerChoiceMatch, celebrationID: UUID?)
        /// What a day is still waiting for, under its answers.
        case waiting(DailyChatRound.Waiting)
        case message(ThreadChatMessage)
        /// The card that opens a memory's or a story's chat.
        case subjectHeader(ThreadChatHeader)
        /// The partner's typing dots, after the newest message.
        case typing
    }

    let id: String
    let kind: Kind
    let isCurrentUser: Bool
    let createdAt: Date
    let groupContext: ThreadChatGroupContext
    let status: ThreadChatMessageStatus?
    let quotedPreview: ThreadChatReplyPreview?
    /// The emoji reactions on a message or an answer, shown on its bubble's corner.
    var reactions: [EmojiReaction] = []

    var message: ThreadChatMessage? {
        if case let .message(message) = kind { return message }
        return nil
    }

    var answer: DailyQuestionAnswerDetail? {
        if case let .answer(answer, _) = kind { return answer }
        return nil
    }

    var isAnswer: Bool { answer != nil }
}

/// The chat list worked out from the page's data: ExyteChat's messages and the row
/// models the cells draw from. Built in one pass and cached until the data changes,
/// so scrolling and unrelated redraws never redo it. Ported from Tidex's chat projection.
struct ThreadChatProjection {
    struct Input: Equatable {
        /// Every day the question came up, oldest first. Empty outside a question's chat.
        let rounds: [DailyChatRound]
        let messages: [ThreadChatMessage]
        let currentUserID: UUID?
        let partnerName: String
        let youName: String
        var partnerIsTyping = false
        var partnerLastReadMessageID: UUID?
        /// The reactions on the messages and answers.
        var reactions: [ThreadChatItemID: [EmojiReaction]] = [:]
        /// What a memory's or a story's chat is about, shown before the first message.
        var header: ThreadChatHeader?
    }

    static let questionRowPrefix = "question-"
    static let answerRowPrefix = "answer-"
    static let matchRowPrefix = "match-"
    static let waitingRowPrefix = "waiting-"
    static let typingRowID = "typing-indicator"
    static let headerRowID = "subject-header"
    /// A message its sender took back. The long-press menu has nothing to offer on it.
    static let deletedRowPrefix = "deleted-"

    /// The row that opens a day, which the page scrolls to.
    static func questionRowID(for instanceID: UUID) -> String {
        questionRowPrefix + instanceID.uuidString
    }

    /// Rows with nothing to reply to, report, or edit: no long-press menu.
    static func isDecorationRowID(_ id: String) -> Bool {
        id == typingRowID || id == headerRowID || id.hasPrefix(matchRowPrefix) || id.hasPrefix(waitingRowPrefix)
    }

    let exyteMessages: [ExyteChat.Message]
    let rowsByID: [String: ThreadChatRow]

    static let empty = ThreadChatProjection(exyteMessages: [], rowsByID: [:])

    /// A message keeps its row id when the server confirms it.
    static func rowID(for message: ThreadChatMessage) -> String {
        let id = (message.clientOperationID ?? message.id).uuidString
        return message.isDeleted ? deletedRowPrefix + id : id
    }

    static func answerRowID(for answerID: UUID) -> String {
        answerRowPrefix + answerID.uuidString
    }

    /// The quote of what a reply points at. `messages` finds a quoted message by id.
    static func preview(
        of target: ThreadChatItemID,
        messages: [UUID: ThreadChatMessage],
        input: Input
    ) -> ThreadChatReplyPreview {
        switch target {
        case let .message(id):
            preview(of: messages[id], id: id, input: input)
        case let .answer(id):
            answerPreview(of: id, input: input)
        }
    }

    static func preview(
        of message: ThreadChatMessage?,
        id: UUID,
        input: Input
    ) -> ThreadChatReplyPreview {
        let isOwn = message?.senderUserID == input.currentUserID
        if let message, message.isDeleted {
            return ThreadChatReplyPreview(
                target: .message(id),
                senderName: isOwn ? input.youName : input.partnerName,
                snippet: nil,
                isVoice: false,
                isDeleted: true
            )
        }
        return ThreadChatReplyPreview(
            target: .message(id),
            senderName: message == nil ? input.partnerName : (isOwn ? input.youName : input.partnerName),
            snippet: message.map { $0.voice == nil ? $0.body : "" },
            isVoice: message?.voice != nil,
            photos: message?.photos ?? []
        )
    }

    /// The quote of an answer: whose answer it is, and its text, pick, photos or recording.
    static func answerPreview(of answerID: UUID, input: Input) -> ThreadChatReplyPreview {
        let found = input.rounds.lazy.compactMap { round in
            round.answers.first { $0.answerID == answerID }.map { (answer: $0, mediaKind: round.mediaKind) }
        }.first
        guard let found else {
            return ThreadChatReplyPreview(
                target: .answer(answerID),
                senderName: String(localized: .dailyChatReplyAnswerTitle),
                snippet: nil,
                isVoice: false
            )
        }
        let answer = found.answer
        let isVoice = answer.hasMedia && found.mediaKind == .voice
        let pickedName = answer.selectedUserID.map { $0 == input.currentUserID ? input.youName : input.partnerName }
        let snippet = answer.textBody?.trimmedNonEmpty ?? answer.selectedOptionLabel ?? pickedName ?? ""
        return ThreadChatReplyPreview(
            target: .answer(answerID),
            senderName: answer.isOwnAnswer
                ? String(localized: .dailyChallengeYourAnswerTitle)
                : String(localized: .dailyChatAnswerPartnerTitle(input.partnerName)),
            snippet: isVoice ? "" : snippet,
            isVoice: isVoice,
            photos: answer.hasMedia && !isVoice
                ? answer.mediaAssetIDs.map { ThreadChatPhoto(mediaAssetID: $0) }
                : []
        )
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

    /// Marks the row a quote jumped to and the answer being revealed, so only those
    /// rows' messages change and only they redraw.
    func highlighting(_ rowID: String?, revealing revealingRowID: String? = nil) -> [ExyteChat.Message] {
        guard rowID != nil || revealingRowID != nil else { return exyteMessages }
        return exyteMessages.map { message in
            let mark = message.id == rowID ? "highlight" : message.id == revealingRowID ? "reveal" : nil
            guard let mark else { return message }
            var marked = message
            marked.triggerRedraw = Self.redrawToken(of: [message.triggerRedraw?.uuidString, mark])
            return marked
        }
    }
}

/// Keeps the last projection and rebuilds it only when its input changed.
@MainActor
final class ThreadChatProjectionStore {
    private var cachedInput: ThreadChatProjection.Input?
    private var cachedProjection = ThreadChatProjection.empty

    func projection(for input: ThreadChatProjection.Input) -> ThreadChatProjection {
        guard cachedInput != input else { return cachedProjection }
        cachedInput = input
        cachedProjection = ThreadChatProjection.make(input: input)
        return cachedProjection
    }
}
