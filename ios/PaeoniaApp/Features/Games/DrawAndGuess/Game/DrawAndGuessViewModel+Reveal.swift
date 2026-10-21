import Foundation

// The reveal: moving past a result.
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

    /// The finished round this person just drew, for the screen that waits for the partner's next
    /// word. The drawer can leave the result before the guesser reacts, so a reaction shows up there.
    var myLastDrawnRoundID: UUID? {
        guard phase == .waitingForWord, let userID = currentUserID, let round, round.isFinished,
              round.isDrawer(userID)
        else { return nil }
        return round.id
    }
}
