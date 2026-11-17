import Foundation

/// One card per question conversation. Anything that waits for the user, such as an unanswered
/// partner question, a partner answer not yet seen or an unread message, stays above the timeline.
nonisolated struct QuestionsTabContent {
    let waitingForYou: [QuestionsTabRow]
    let recent: [QuestionsTabRow]

    /// `isNew` says whether a question has a partner answer or message the user hasn't seen.
    init(
        current: [DailyChallengeQuestion],
        topics: [DailyChallengeQuestion],
        history: [DailyChallengeQuestion],
        conversations: [SubjectConversation],
        messageDate: (DailyChallengeQuestion) -> Date?,
        isNew: (DailyChallengeQuestion) -> Bool
    ) {
        // Current snapshots win over a history read of the same answer round.
        let byID = Dictionary((history + topics + current).map { ($0.id, $0) }, uniquingKeysWith: { _, live in live })
        // An unanswered round stands for its question. Otherwise the round with the latest activity does.
        let questions = Dictionary(grouping: byID.values, by: \.questionID).values.compactMap { rounds in
            rounds.filter(\.isAwaitingCurrentUserAnswer).max {
                ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString)
            } ?? rounds.max {
                ($0.conversationActivityDate(messageDate: messageDate($0)), $0.startsAt, $0.id.uuidString)
                    < ($1.conversationActivityDate(messageDate: messageDate($1)), $1.startsAt, $1.id.uuidString)
            }
        }
        let rows = questions.map(QuestionsTabRow.question) + conversations.map(QuestionsTabRow.conversation)
        func date(_ row: QuestionsTabRow) -> Date {
            switch row {
            case .question(let question): question.conversationActivityDate(messageDate: messageDate(question))
            case .conversation(let conversation):
                max(conversation.summary.lastMessageAt ?? .distantPast, conversation.startedAt)
            }
        }
        func waitsForUser(_ row: QuestionsTabRow) -> Bool {
            switch row {
            case .question(let question): question.isAwaitingCurrentUserAnswer || isNew(question)
            case .conversation(let conversation): conversation.isUnread
            }
        }
        let sorted = rows.sorted {
            if date($0) != date($1) { return date($0) > date($1) }
            return $0.id.uuidString < $1.id.uuidString
        }
        waitingForYou = sorted.filter(waitsForUser)
        recent = sorted.filter { !waitsForUser($0) }
    }
}
