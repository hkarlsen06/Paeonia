import Foundation

/// The score as the couple's play style shows it. The server keeps all three
/// totals, so switching the style loses nothing.
nonisolated enum DrawAndGuessScore: Equatable, Sendable {
    /// One score for the couple.
    case together(total: Int)
    case against(mine: Int, partner: Int)

    init(game: RemoteDrawAndGuessGame, playStyle: GamePlayStyle) {
        switch playStyle {
        case .together:
            self = .together(total: game.sharedPoints)
        case .against:
            self = .against(mine: game.myPoints, partner: game.partnerPoints)
        }
    }

}
