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
}

// MARK: Turn label

/// How a player's ring in the players row looks.
nonisolated enum BoardGameRingState: Equatable, Sendable {
    /// A faint ring in the piece color.
    case resting
    /// The player's turn. The ring glows and fades in a slow rhythm.
    case breathing
    /// The player won. The ring stays lit.
    case steady
}

extension BoardGameTurnLabel {
    func ringState(forMe isMe: Bool) -> BoardGameRingState {
        switch self {
        case .yourTurn: isMe ? .breathing : .resting
        case .partnerTurn: isMe ? .resting : .breathing
        case .youWon: isMe ? .steady : .resting
        case .partnerWon: isMe ? .resting : .steady
        case .draw: .resting
        }
    }

    /// What VoiceOver reads on the lit avatar. A draw lights none.
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

// MARK: Ring pulse

/// The opacity of the glowing ring over time. It starts dim, rises to its peak
/// halfway through each period and falls back.
nonisolated enum BoardGameRingPulse {
    static let period: TimeInterval = 2.4
    static let low = 0.45
    static let high = 0.9
    /// Reduce Motion holds the ring still at this opacity.
    static let still = 0.7

    static func opacity(at time: TimeInterval) -> Double {
        let phase = (1 - cos(2 * .pi * time / period)) / 2
        return low + (high - low) * phase
    }
}
