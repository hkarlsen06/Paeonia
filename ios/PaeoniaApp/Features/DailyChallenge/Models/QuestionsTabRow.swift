import Foundation

/// A memory or a story someone has written about, listed on the Questions tab with the
/// question chats. It belongs to the day the memory was added or the story was posted, not
/// the memory's own date, which can be years back.
nonisolated struct SubjectConversation: Identifiable, Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        case memory(MemoryRecord)
        case story(Story)
        case game(GameChatSubject)
    }

    let subject: Subject
    let summary: ThreadChatSummary
    /// The partner wrote in the chat after the user last read it.
    let isUnread: Bool

    var id: UUID {
        switch subject {
        case .memory(let record): record.snapshot.memoryID
        case .story(let story): story.id
        case .game(let source): source.id
        }
    }

    /// When the memory was added or the story was posted: the row's place in the timeline.
    var startedAt: Date {
        switch subject {
        case .memory(let record): record.snapshot.createdAt
        case .story(let story): story.createdAt
        case .game: summary.lastMessageAt ?? summary.createdAt
        }
    }

    /// The card that opens the chat, the same one the memory page or the story viewer uses.
    @MainActor
    func header(people: StoryPeople) -> ThreadChatHeader {
        switch subject {
        case .memory(let record): ThreadChatHeader(memory: record)
        case .story(let story): .story(story, people: people)
        case .game(let source): .game(source)
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

    /// Handled rows use their historical timestamp, then a stable UUID tie-break.
    static func timelineOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

}
