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

extension DrawAndGuessRoundView {
    var conversationResult: GameConversationResult? {
        guard state == .solved || state == .missed, let drawingMediaAssetID else { return nil }
        return .drawAndGuess(
            RemoteDrawAndGuessHistoryRound(
                id: id, roundNumber: number, drawerUserID: drawerUserID, guesserUserID: guesserUserID,
                word: word, difficulty: difficulty, points: points, state: state,
                drawingMediaAssetID: drawingMediaAssetID, solveMs: solveMs, speedBonus: speedBonus,
                firstTryBonus: firstTryBonus, hintsUsed: hintsUsed, attemptCount: attempts.count,
                personalBest: personalBest, startedAt: startedAt, endedAt: endedAt
            ), guesses: attempts.map(\.text))
    }
}
