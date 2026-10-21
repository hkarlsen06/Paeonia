import ExyteChat
import Foundation

/// Where a bubble sits in a run of messages from the same person, which decides its
/// corner shape and whether the avatar shows. Ported from Tidex's chat grouping.
nonisolated enum DailyChatGroupPosition: Hashable {
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
        guard !lhs.hasMedia, !rhs.hasMedia, lhs.replyTo == nil, rhs.replyTo == nil else {
            return false
        }
        let gap = rhs.createdAt.timeIntervalSince(lhs.createdAt)
        return gap >= 0 && gap <= maximumGap
    }
}

/// The quoted message or answer shown above a reply, and in the composer while writing one.
struct DailyChatReplyPreview: Hashable {
    let target: DailyChatItemID
    let senderName: String
    /// Nil when the quoted message or answer is no longer in the chat.
    let snippet: String?
    let isVoice: Bool
    /// The quoted message's photos, shown as small thumbnails.
    var photos: [DailyQuestionChatPhoto] = []

    var isAnswer: Bool { target.answerID != nil }
}

/// The small line under your own messages. Like Tidex: Sending and Not sent show on
/// every message in that state, Read on the newest one the partner has read, and
/// Sent on your newest message.
nonisolated enum DailyChatMessageStatus: Hashable {
    case sending
    case sent
    case read
    case failed
}

/// One row of the chat list, worked out once per change instead of in every cell.
struct DailyChatRow {
    enum Kind {
        case question(String)
        /// An answer, with the kind of media this day's question takes, since a question
        /// that comes back can take another kind.
        case answer(DailyQuestionAnswerDetail, mediaKind: DailyChallengeAnswerKind)
        /// How two partner-choice picks line up, above the day's answers.
        case partnerChoiceMatch(PartnerChoiceMatch, celebrationID: UUID?)
        /// What a day is still waiting for, under its answers.
        case waiting(DailyChatRound.Waiting)
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
    /// The emoji reactions on a message or an answer, shown on its bubble's corner.
    var reactions: [DailyChatReaction] = []

    var message: DailyQuestionChatMessage? {
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
struct DailyChatProjection {
    struct Input: Equatable {
        /// Every day the question came up, oldest first.
        let rounds: [DailyChatRound]
        let messages: [DailyQuestionChatMessage]
        let currentUserID: UUID?
        let partnerName: String
        let youName: String
        var partnerIsTyping = false
        var partnerLastReadMessageID: UUID?
        /// The reactions on the messages and answers.
        var reactions: [DailyChatItemID: [DailyChatReaction]] = [:]
    }

    static let questionRowPrefix = "question-"
    static let answerRowPrefix = "answer-"
    static let matchRowPrefix = "match-"
    static let waitingRowPrefix = "waiting-"
    static let typingRowID = "typing-indicator"

    /// The row that opens a day, which the page scrolls to.
    static func questionRowID(for instanceID: UUID) -> String {
        questionRowPrefix + instanceID.uuidString
    }

    /// Rows with nothing to reply to, report, or edit: no long-press menu.
    static func isDecorationRowID(_ id: String) -> Bool {
        id == typingRowID || id.hasPrefix(matchRowPrefix) || id.hasPrefix(waitingRowPrefix)
    }

    let exyteMessages: [ExyteChat.Message]
    let rowsByID: [String: DailyChatRow]

    static let empty = DailyChatProjection(exyteMessages: [], rowsByID: [:])

    /// A message keeps its row id when the server confirms it.
    static func rowID(for message: DailyQuestionChatMessage) -> String {
        (message.clientOperationID ?? message.id).uuidString
    }

    static func answerRowID(for answerID: UUID) -> String {
        answerRowPrefix + answerID.uuidString
    }

    /// The quote of what a reply points at. `messages` finds a quoted message by id.
    static func preview(
        of target: DailyChatItemID,
        messages: [UUID: DailyQuestionChatMessage],
        input: Input
    ) -> DailyChatReplyPreview {
        switch target {
        case let .message(id):
            preview(of: messages[id], id: id, input: input)
        case let .answer(id):
            answerPreview(of: id, input: input)
        }
    }

    static func preview(
        of message: DailyQuestionChatMessage?,
        id: UUID,
        input: Input
    ) -> DailyChatReplyPreview {
        let isOwn = message?.senderUserID == input.currentUserID
        return DailyChatReplyPreview(
            target: .message(id),
            senderName: message == nil ? input.partnerName : (isOwn ? input.youName : input.partnerName),
            snippet: message.map { $0.voice == nil ? $0.body : "" },
            isVoice: message?.voice != nil,
            photos: message?.photos ?? []
        )
    }

    /// The quote of an answer: whose answer it is, and its text, pick, photos or recording.
    static func answerPreview(of answerID: UUID, input: Input) -> DailyChatReplyPreview {
        let found = input.rounds.lazy.compactMap { round in
            round.answers.first { $0.answerID == answerID }.map { (answer: $0, mediaKind: round.mediaKind) }
        }.first
        guard let found else {
            return DailyChatReplyPreview(
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
        return DailyChatReplyPreview(
            target: .answer(answerID),
            senderName: answer.isOwnAnswer
                ? String(localized: .dailyChallengeYourAnswerTitle)
                : String(localized: .dailyChatAnswerPartnerTitle(input.partnerName)),
            snippet: isVoice ? "" : snippet,
            isVoice: isVoice,
            photos: answer.hasMedia && !isVoice
                ? answer.mediaAssetIDs.map { DailyQuestionChatPhoto(mediaAssetID: $0) }
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
