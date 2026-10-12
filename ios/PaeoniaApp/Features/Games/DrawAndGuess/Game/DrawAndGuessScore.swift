import Foundation

/// The score as the couple's play style shows it. The server keeps all three
/// totals, so switching the style loses nothing.
nonisolated enum DrawAndGuessScore: Equatable, Sendable {
    /// One score for the couple.
    case together(total: Int)
    case against(mine: Int, partner: Int)

    enum Leader: Equatable, Sendable {
        case me
        case partner
        case tied
    }

    init(game: RemoteDrawAndGuessGame, playStyle: GamePlayStyle) {
        switch playStyle {
        case .together:
            self = .together(total: game.sharedPoints)
        case .against:
            self = .against(mine: game.myPoints, partner: game.partnerPoints)
        }
    }

    /// Nil when the couple plays together, because nobody leads.
    var leader: Leader? {
        guard case let .against(mine, partner) = self else {
            return nil
        }
        if mine == partner {
            return .tied
        }
        return mine > partner ? .me : .partner
    }
}
