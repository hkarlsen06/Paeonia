import Foundation

/// The attention list has one card per conversation. Answer rounds remain separate in history.
nonisolated struct QuestionsTabContent {
    let attention: [QuestionsTabRow]
    let recent: [QuestionsTabRow]

    var shownQuestionIDs: Set<UUID> {
        Set((attention + recent).compactMap { row in
            guard case .question(let question) = row else { return nil }
            return question.id
        })
    }

    init(
        current: [DailyChallengeQuestion],
        topics: [DailyChallengeQuestion],
        history: [DailyChallengeQuestion],
        conversations: [SubjectConversation],
        today: String,
        timeZone: TimeZone,
        attentionDate: (DailyChallengeQuestion) -> Date?
    ) {
        // Current snapshots win over a history read of the same answer round.
        let byID = Dictionary((history + topics + current).map { ($0.id, $0) }, uniquingKeysWith: { _, live in live })
        let grouped = Dictionary(grouping: byID.values.filter { attentionDate($0) != nil }, by: \.questionID)
        let questions = grouped.values.compactMap { rounds in
            rounds.max { ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString) }
        }
        let promotedQuestionIDs = Set(questions.map(\.questionID))
        let rows = questions.map(QuestionsTabRow.question)
            + conversations.filter(\.isUnread).map(QuestionsTabRow.conversation)
        attention = rows.sorted { lhs, rhs in
            func date(_ row: QuestionsTabRow) -> Date {
                switch row {
                case .question(let question): attentionDate(question) ?? question.latestAnswerDate
                case .conversation(let conversation): conversation.summary.lastMessageAt ?? conversation.startedAt
                }
            }
            if date(lhs) != date(rhs) { return date(lhs) > date(rhs) }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        recent = (
            current.filter { !promotedQuestionIDs.contains($0.questionID) }.map(QuestionsTabRow.question)
                + conversations.filter { !$0.isUnread && $0.isToday(today, timeZone: timeZone) }
                    .map(QuestionsTabRow.conversation)
        ).sorted(by: QuestionsTabRow.timelineOrder)
    }
}
