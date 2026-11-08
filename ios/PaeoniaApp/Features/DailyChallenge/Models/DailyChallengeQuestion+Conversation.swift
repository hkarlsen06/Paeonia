import Foundation

nonisolated extension DailyChallengeQuestion {
    func conversationActivityDate(messageDate: Date?) -> Date {
        max(latestAnswerDate, isChatAvailable ? messageDate ?? .distantPast : .distantPast)
    }

    /// Partner content enters the list only after this round has been revealed.
    func answerPreview(participants: DailyChallengeParticipants) -> String? {
        let answers = [ownAnswerDetail, hasRevealedPartnerAnswer ? partnerAnswerDetail : nil]
            .compactMap { $0 }.filter(\.canViewAnswer)
        guard let answer = answers.max(by: { $0.answeredAt < $1.answeredAt }) else { return nil }
        let text: String
        if let body = answer.textBody?.trimmedNonEmpty {
            text = body
        } else if let option = answer.selectedOptionLabel?.trimmedNonEmpty {
            text = option
        } else if let selected = answer.selectedUserID {
            text = selected == participants.currentUserID
                ? participants.currentDisplayName ?? String(localized: .chatsCoupleChatYou)
                : participants.partnerName
        } else if answer.hasMedia {
            text = String(localized: .chatsMediaAnswerPreview)
        } else {
            return nil
        }
        let name = answer.isOwnAnswer ? String(localized: .chatsCoupleChatYou) : participants.partnerName
        return String(localized: .chatsCoupleChatPreview(name, text))
    }
}
