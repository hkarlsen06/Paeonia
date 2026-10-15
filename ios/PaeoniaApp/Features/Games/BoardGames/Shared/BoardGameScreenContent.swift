import SwiftUI

// What the shared board game shell shows, as plain values. The view model maps
// the game onto these, and the views in this folder draw them.

/// One player as the shell draws them. `style` holds the piece color and mark.
struct BoardGamePlayerInfo: Equatable {
    let name: String
    let photoAssetID: UUID?
    let style: BoardPieceStyle
}

/// Whose turn it is, or how the game ended, for the players row.
nonisolated enum BoardGameTurnLabel: Equatable, Hashable, Sendable {
    case yourTurn
    case partnerTurn
    case youWon
    case partnerWon
    case draw
}

nonisolated enum BoardGameStakeState: Equatable, Sendable {
    case hidden
    /// The starter can write or change the stake until the first move.
    case writable
    case fixed(String)
}

nonisolated enum BoardGamePartnerStatus: Equatable, Sendable {
    case here
    case away
}

/// The score as the couple's play style shows it.
nonisolated enum BoardGameScore: Equatable, Sendable {
    case against(mine: Int, partner: Int)
    case together(games: Int)
}

nonisolated enum BoardGameWinner: Equatable, Sendable {
    case me
    case partner
    case draw
}

/// The finished game, for the result panel.
nonisolated struct BoardGameResultContent: Equatable, Sendable {
    let winner: BoardGameWinner
    let playStyle: GamePlayStyle
    let stake: String?
    /// Tallies after this game. The panel counts the winner's (or the couple's games) up from one less.
    let myWins: Int
    let partnerWins: Int
    let gamesFinished: Int
    /// An ending the person missed, shown before the next game. The action reads "Continue" instead of "Play again".
    let isMissedEnding: Bool
}

/// Everything the shell draws around the board.
struct BoardGameShellContent: Equatable {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let stake: BoardGameStakeState
    let partnerStatus: BoardGamePartnerStatus
    /// Goes up with each extra turn of mine, so the status row can pop "Another turn".
    let extraTurnCount: Int
    let score: BoardGameScore?
    /// A game's own line for the status row, shown instead of who is here.
    var hint: LocalizedStringResource?
    /// Ludo's color circles before the player's first move. Nil in the other games and after.
    var colorChoice: BoardGameColorChoice?
}

// MARK: Turn label

extension BoardGameTurnLabel {
    /// True for the player whose turn it is, or who won. A draw marks neither.
    func isActive(forMe isMe: Bool) -> Bool {
        switch self {
        case .yourTurn, .youWon: isMe
        case .partnerTurn, .partnerWon: !isMe
        case .draw: false
        }
    }

    /// What VoiceOver reads on the active avatar. A draw marks none.
    func spoken(partnerName: String) -> LocalizedStringResource? {
        switch self {
        case .yourTurn: .boardGamesTurnYours
        case .partnerTurn: .boardGamesTurnPartner(partnerName)
        case .youWon: .boardGamesTurnYouWon
        case .partnerWon: .boardGamesTurnPartnerWon(partnerName)
        case .draw: nil
        }
    }
}

// MARK: Score

extension BoardGameScore {
    /// The score as VoiceOver reads it, for example "You 4 wins, Robin 3 wins".
    func spoken(partnerName: String) -> LocalizedStringResource {
        switch self {
        case let .against(mine, theirs):
            .boardGamesScoreAgainstA11Y(
                String(localized: .boardGamesScoreWins(mine)),
                partnerName,
                String(localized: .boardGamesScoreWins(theirs))
            )
        case let .together(games):
            .boardGamesScoreTogetherA11Y(String(localized: .boardGamesScoreGames(games)))
        }
    }
}
