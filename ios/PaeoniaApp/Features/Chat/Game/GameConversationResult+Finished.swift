import Foundation

extension RemoteMindMeldGame {
    var conversationResult: GameConversationResult? {
        guard isFinished else { return nil }
        return .mindMeld(
            RemoteMindMeldHistoryGame(
                id: id, gameNumber: gameNumber, state: state, endReason: endReason,
                endedByUserID: endedByUserID, createdAt: createdAt, endedAt: endedAt, meldNumber: meldNumber,
                rounds: rounds.compactMap { round in
                    guard round.state == .revealed, let mine = round.myWord,
                        let theirs = round.partnerWord, let outcome = round.outcome
                    else { return nil }
                    return RemoteMindMeldHistoryRound(
                        roundNumber: round.roundNumber, myWord: mine, partnerWord: theirs,
                        outcome: outcome, countedByUserID: round.countedByUserID
                    )
                }
            ))
    }
}
