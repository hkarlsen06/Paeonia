import Foundation

/// What the server sends for a question's page: the chat's thread, when it exists, and
/// every day the question came up, oldest first. Each day has the rows and answers
/// the viewer may read, in the same shape as the daily snapshot. The server applies
/// the reveal rule to each day on its own, and sends the reactions on the answers the
/// viewer may read.
nonisolated struct DailyQuestionChatRoundsRow: Codable, Equatable, Sendable {
    let threadID: UUID?
    let questions: [DailyQuestionRow]
    let answerDetails: [DailyAnswerDetailRow]
    let reactions: [DailyAnswerReaction]

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case questions
        case answerDetails = "answer_details"
        case reactions
    }

    /// Every day in the list belongs to this couple. A copy kept on this phone from an earlier
    /// relationship is never shown in a later one.
    func isForCouple(_ coupleID: UUID) -> Bool {
        questions.allSatisfy { $0.coupleID == coupleID }
    }

    /// The rounds as questions, oldest first.
    func rounds(locale: Locale = .current) -> [DailyChallengeQuestion] {
        DailyChallengeQuestion.list(
            rows: questions,
            answerDetails: answerDetails,
            locale: locale
        )
    }
}

/// The arguments of the question page's query.
nonisolated struct QuestionChatRequest: Encodable {
    let coupleID: UUID
    let questionID: UUID
    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case questionID = "p_question_id"
    }
}
