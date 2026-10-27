import Foundation

extension BoardGameViewModel {
    var conversationResult: GameConversationResult? {
        guard !isShowingMissedEnding, let game = document.state?.game(kind),
            game.gameNumber == displayedGameNumber, let finishedAt = game.finishedAt
        else { return nil }
        return .board(
            kind,
            RemoteBoardGameHistoryGame(
                gameNumber: game.gameNumber, firstUserID: game.firstUserID, moves: game.moves,
                winnerUserID: game.winnerUserID, winLine: game.winLine, stake: game.stake,
                startedAt: game.startedAt, finishedAt: finishedAt
            ))
    }
}
