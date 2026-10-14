#if DEBUG
import SwiftUI

/// Sample players and results for the previews in this folder.
enum BoardGamePreviewData {
    static let me = BoardGamePlayerInfo(
        name: "Hjalmar",
        photoAssetID: nil,
        style: BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "H")
    )

    static let partner = BoardGamePlayerInfo(
        name: "Robin",
        photoAssetID: nil,
        style: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "R")
    )

    static func shell(
        turn: BoardGameTurnLabel = .yourTurn,
        stake: BoardGameStakeState = .fixed("Loser makes coffee"),
        partnerStatus: BoardGamePartnerStatus = .here,
        colorChoice: BoardGameColorChoice? = nil
    ) -> BoardGameShellContent {
        BoardGameShellContent(
            me: me,
            partner: partner,
            turn: turn,
            stake: stake,
            partnerStatus: partnerStatus,
            extraTurnCount: 0,
            score: .against(mine: 4, partner: 3),
            colorChoice: colorChoice
        )
    }

    static func result(
        winner: BoardGameWinner = .me,
        playStyle: GamePlayStyle = .against,
        stake: String? = "Loser makes coffee",
        isMissedEnding: Bool = false
    ) -> BoardGameResultContent {
        BoardGameResultContent(
            winner: winner,
            playStyle: playStyle,
            stake: stake,
            myWins: 4,
            partnerWins: 3,
            gamesFinished: 13,
            isMissedEnding: isMissedEnding
        )
    }

    /// A stand-in for a board: a square that fits the space it is given.
    static var board: some View {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
            .fill(.paeoniaBackgroundPrimary)
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .aspectRatio(1, contentMode: .fit)
    }
}
#endif
