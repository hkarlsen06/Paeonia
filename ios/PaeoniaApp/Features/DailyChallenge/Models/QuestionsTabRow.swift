import Foundation

/// A memory or a story someone has written about, listed on the Questions tab with the
/// question chats. It belongs to the day the memory was added or the story was posted, not
/// the memory's own date, which can be years back.
nonisolated struct SubjectConversation: Identifiable, Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        case memory(MemoryRecord)
        case story(Story)
    }

    let subject: Subject
    let summary: ThreadChatSummary
    /// The partner wrote in the chat after the user last read it.
    let isUnread: Bool

    var id: UUID {
        switch subject {
        case .memory(let record): record.snapshot.memoryID
        case .story(let story): story.id
        }
    }

    /// When the memory was added or the story was posted: the row's place in the timeline.
    var startedAt: Date {
        switch subject {
        case .memory(let record): record.snapshot.createdAt
        case .story(let story): story.createdAt
        }
    }

    /// The phone's local date of `startedAt`, as `yyyy-MM-dd`.
    var localDate: String {
        MemoryTimeline.localDateString(for: startedAt)
    }

    /// Whether the row sits in today's list rather than under an earlier day. A row dated
    /// after `today` (the phone's day turned before the couple's) counts as today.
    func isToday(_ today: String) -> Bool {
        localDate >= today
    }

    /// The card that opens the chat, the same one the memory page or the story viewer uses.
    @MainActor
    func header(people: StoryPeople) -> ThreadChatHeader {
        switch subject {
        case .memory(let record): ThreadChatHeader(memory: record)
        case .story(let story): .story(story, people: people)
        }
    }
}

/// One row on the Questions tab: a question, or the chat about a memory or a story.
nonisolated enum QuestionsTabRow: Identifiable, Equatable, Sendable {
    case question(DailyChallengeQuestion)
    case conversation(SubjectConversation)

    var id: UUID {
        switch self {
        case .question(let question): question.id
        case .conversation(let conversation): conversation.id
        }
    }

    /// The row's place in the timeline: a question's latest answer, when a memory was added
    /// or a story posted.
    var sortDate: Date {
        switch self {
        case .question(let question): question.latestAnswerDate
        case .conversation(let conversation): conversation.startedAt
        }
    }

    /// Questions tab order. A question the partner answered that the user can still
    /// answer comes first, then rows with something new from the partner (a question's
    /// answer or chat message, an unread message about a memory or a story), then the
    /// rest. Within each tier the newest comes first (`timelineOrder`).
    static func questionsTabOrder(
        _ lhs: Self,
        _ rhs: Self,
        isNew: (DailyChallengeQuestion) -> Bool = { _ in false }
    ) -> Bool {
        func tier(_ row: Self) -> Int {
            switch row {
            case .question(let question):
                if question.isAwaitingCurrentUserAnswer { return 0 }
                return isNew(question) ? 1 : 2
            case .conversation(let conversation):
                return conversation.isUnread ? 1 : 2
            }
        }
        let lhsTier = tier(lhs)
        let rhsTier = tier(rhs)
        if lhsTier != rhsTier {
            return lhsTier < rhsTier
        }
        return timelineOrder(lhs, rhs)
    }

    /// Newest first, then a stable id tiebreak. Today's list uses it within a tier, and
    /// each earlier day uses it for its rows.
    static func timelineOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Today's list: the questions it shows and the memory and story chats from `today`,
    /// in Questions tab order.
    static func todayRows(
        questions: [DailyChallengeQuestion],
        conversations: [SubjectConversation],
        today: String,
        isNew: (DailyChallengeQuestion) -> Bool = { _ in false }
    ) -> [Self] {
        let rows = questions.map(Self.question)
            + conversations.filter { $0.isToday(today) }.map(Self.conversation)
        return rows.sorted { questionsTabOrder($0, $1, isNew: isNew) }
    }
}
