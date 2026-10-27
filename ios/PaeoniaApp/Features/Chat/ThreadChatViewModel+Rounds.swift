import Foundation

extension ThreadChatViewModel {
    /// Every day of the question, oldest first. The server's list decides what exists and
    /// what is readable. The day the page was opened from fills in until it has answered.
    /// Empty in a memory's or a story's chat.
    var rounds: [DailyChallengeQuestion] {
        guard let question else { return [] }
        return DailyChatRounds.merged(loaded: loadedRounds, entry: question, serverConfirmed: roundsAreConfirmed)
    }

    /// A question's chat opens once any day of the question has both answers. A memory's or a
    /// story's chat is open to both partners from the start.
    var isChatAvailable: Bool {
        guard participants.currentUserID != nil else { return false }
        return header?.gameLoadState != .removed && (question == nil || DailyChatRounds.isChatAvailable(rounds))
    }

    /// The days as the page draws them. `celebratingInstanceID` is the day whose
    /// partner-choice match plays its small celebration.
    func chatRounds(celebrating celebratingInstanceID: UUID? = nil) -> [DailyChatRound] {
        let chatIsOpen = DailyChatRounds.isChatAvailable(rounds)
        return rounds.map {
            DailyChatRound(
                question: $0,
                participants: participants,
                chatIsOpen: chatIsOpen,
                celebratesMatch: $0.id == celebratingInstanceID
            )
        }
    }

}
