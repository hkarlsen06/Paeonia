import Foundation

/// One card per question conversation, with unanswered partner questions kept above the timeline.
nonisolated struct QuestionsTabContent {
    let waitingForYou: [QuestionsTabRow]
    let recent: [QuestionsTabRow]

    init(
        current: [DailyChallengeQuestion],
        topics: [DailyChallengeQuestion],
        history: [DailyChallengeQuestion],
        conversations: [SubjectConversation],
        messageDate: (DailyChallengeQuestion) -> Date?
    ) {
        // Current snapshots win over a history read of the same answer round.
        let byID = Dictionary((history + topics + current).map { ($0.id, $0) }, uniquingKeysWith: { _, live in live })
        let grouped = Dictionary(grouping: byID.values, by: \.questionID)
        let waiting = grouped.values.compactMap { rounds in
            rounds.filter(\.isAwaitingCurrentUserAnswer).max {
                ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString)
            }
        }
        let waitingIDs = Set(waiting.map(\.questionID))
        waitingForYou = waiting.map(QuestionsTabRow.question).sorted(by: QuestionsTabRow.timelineOrder)
        let questions = grouped.compactMap { questionID, rounds -> DailyChallengeQuestion? in
            guard !waitingIDs.contains(questionID) else { return nil }
            return rounds.max {
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
        recent = rows.sorted {
            if date($0) != date($1) { return date($0) > date($1) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
