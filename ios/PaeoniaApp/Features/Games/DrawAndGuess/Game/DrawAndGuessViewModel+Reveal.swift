import Foundation

// The reveal: moving past a result, and the guesser's reaction to it.
extension DrawAndGuessViewModel {
    /// Leaves the reveal for the next turn. The "I have seen this result" mark is
    /// saved on the phone first, so the screen moves on at once without the
    /// network. The server keeps it per person, so a second phone and a fresh
    /// install do not show the same result again.
    func continueFromReveal() async {
        guard phase == .reveal, let round else { return }
        let payload = GameResultSeenPayload(roundID: round.id, createdAt: dependencies.now())
        await enqueue(
            .markGameRoundResultSeen,
            scope: "game-result-seen:\(round.id.uuidString.lowercased())",
            payload: payload
        )
    }

    /// The guesser's reaction to the round this person just drew, for the screen
    /// that waits for the partner's next word. The drawer can leave the result
    /// before the guesser reacts, so the reaction shows up there instead.
    var reactionToMyLastDrawing: DrawAndGuessReaction? {
        guard phase == .waitingForWord, let userID = currentUserID, let round, round.isFinished,
              round.isDrawer(userID)
        else { return nil }
        return round.guesserReaction
    }

    /// The guesser's reaction to the finished round. Choosing the one that is
    /// already chosen clears it. The reaction shows on the phone at once and goes
    /// out when the phone is online. The last one made wins.
    func react(_ reaction: DrawAndGuessReaction) async {
        guard phase == .reveal, let round, round.guesserUserID == currentUserID else { return }
        let payload = GameReactionPayload(
            roundID: round.id,
            reaction: round.guesserReaction == reaction ? nil : reaction,
            createdAt: dependencies.now()
        )
        await enqueue(
            .setGameRoundReaction,
            scope: "game-reaction:\(round.id.uuidString.lowercased())",
            payload: payload
        )
    }
}
