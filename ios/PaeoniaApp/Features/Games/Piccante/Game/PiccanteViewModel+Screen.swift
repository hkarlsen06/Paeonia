import SwiftUI

extension PiccanteViewModel {
    var meInfo: BoardGamePlayerInfo {
        BoardGamePlayerInfo(
            name: participants.currentName, photoAssetID: participants.currentPhotoAssetID,
            style: BoardPieceStyle(
                color: .boardGameMine, mark: nil,
                initial: BoardPieceStyle.initial(of: participants.currentName), owner: .one))
    }

    var partnerInfo: BoardGamePlayerInfo {
        BoardGamePlayerInfo(
            name: partnerName, photoAssetID: participants.partnerPhotoAssetID,
            style: BoardPieceStyle(
                color: .boardGamePartner, mark: nil,
                initial: BoardPieceStyle.initial(of: partnerName), owner: .two))
    }

    var visibleScore: BoardGameScore? {
        guard let score, !score.isEmpty, game?.phase != .finished || revealSettled else { return nil }
        return score
    }

    var showsBiteHint: Bool {
        guard let game else { return false }
        return game.gameNumber == 1 && !game.bites.contains { $0.userID == userID }
    }

    var score: BoardGameScore? {
        guard let game else { return nil }
        return playStyle == .against
            ? .against(mine: game.myWins, partner: game.partnerWins)
            : .together(games: game.gamesFinished)
    }

    var turnLabel: BoardGameTurnLabel {
        guard let game else { return .draw }
        if game.phase == .choosing { return .draw }
        if game.phase == .finished {
            guard revealSettled else { return .draw }
            return game.winnerUserID == userID ? .youWon : .partnerWon
        }
        return isMyTurn ? .yourTurn : .partnerTurn
    }

}
