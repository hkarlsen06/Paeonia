import Foundation

/// A story someone has written about, listed on the Questions tab with the question chats.
/// It belongs to the day the story was posted.
nonisolated struct StoryConversation: Identifiable, Equatable, Sendable {
    let story: Story
    let summary: ThreadChatSummary
    /// The partner wrote in the chat after the user last read it.
    let isUnread: Bool

    var id: UUID { story.id }

    /// The phone's local date the story was posted, as `yyyy-MM-dd`.
    var localDate: String {
        MemoryTimeline.localDateString(for: story.createdAt)
    }

    /// Whether the row sits in today's list rather than under an earlier day. A story
    /// dated after `today` (the phone's day turned before the couple's) counts as today.
    func isToday(_ today: String) -> Bool {
        localDate >= today
    }
}

/// One row on the Questions tab: a question, or the chat about a story.
nonisolated enum QuestionsTabRow: Identifiable, Equatable, Sendable {
    case question(DailyChallengeQuestion)
    case storyChat(StoryConversation)

    var id: UUID {
        switch self {
        case .question(let question): question.id
        case .storyChat(let conversation): conversation.id
        }
    }

    /// The row's place in the timeline: a question's latest answer, a story's posting time.
    var sortDate: Date {
        switch self {
        case .question(let question): question.latestAnswerDate
        case .storyChat(let conversation): conversation.story.createdAt
        }
    }

    /// Questions tab order. A question the partner answered that the user can still
    /// answer comes first, then rows with something new from the partner (a question's
    /// answer or chat message, a story's unread reply), then the rest. Within each tier
    /// the newest comes first (`timelineOrder`).
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
            case .storyChat(let conversation):
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

    /// Today's list: the questions it shows and the story chats from `today`, in
    /// Questions tab order.
    static func todayRows(
        questions: [DailyChallengeQuestion],
        storyChats: [StoryConversation],
        today: String,
        isNew: (DailyChallengeQuestion) -> Bool = { _ in false }
    ) -> [Self] {
        let rows = questions.map(Self.question) + storyChats.filter { $0.isToday(today) }.map(Self.storyChat)
        return rows.sorted { questionsTabOrder($0, $1, isNew: isNew) }
    }
}
