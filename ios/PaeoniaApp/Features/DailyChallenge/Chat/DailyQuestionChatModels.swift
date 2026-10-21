import Foundation

/// A reaction to an answer, as the question's rounds carry it.
nonisolated struct DailyAnswerReaction: Codable, Equatable, Hashable, Sendable {
    let answerID: UUID
    let userID: UUID
    let emoji: String

    var reaction: EmojiReaction {
        EmojiReaction(userID: userID, emoji: emoji)
    }

    enum CodingKeys: String, CodingKey {
        case answerID = "answer_id"
        case userID = "user_id"
        case emoji
    }
}

extension DailyChallengeQuestion {
    /// The partner's answer to this very round is readable. The answer flow and the
    /// "new answer" marks work per round.
    nonisolated var hasRevealedPartnerAnswer: Bool {
        hasOwnAnswer && hasPartnerAnswer && canViewPartnerAnswer
    }

    /// The question's chat can be used. A couple has one chat per question, so it
    /// opens once any round of the question has both answers.
    nonisolated var isChatAvailable: Bool {
        hasRevealedPartnerAnswer || hasSharedRound
    }
}
