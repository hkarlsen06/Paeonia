import Foundation

/// The score as the couple's play style shows it. The server keeps both, so a
/// change of style loses nothing. Only the guesser scores a round.
nonisolated enum GuessMySpotScore: Equatable, Sendable {
    /// One total for the couple.
    case together(total: Int)
    case against(mine: Int, partner: Int)

    init(game: RemoteGuessMySpotGame?, playStyle: GamePlayStyle) {
        switch playStyle {
        case .together:
            self = .together(total: game?.sharedPoints ?? 0)
        case .against:
            self = .against(mine: game?.myPoints ?? 0, partner: game?.partnerPoints ?? 0)
        }
    }

    init(records: RemoteGuessMySpotRecords, playStyle: GamePlayStyle) {
        switch playStyle {
        case .together: self = .together(total: records.sharedPoints)
        case .against: self = .against(mine: records.myPoints, partner: records.partnerPoints)
        }
    }

    /// Nothing scored yet, so the hub shows no badge.
    var isEmpty: Bool {
        switch self {
        case let .together(total): total == 0
        case let .against(mine, partner): mine == 0 && partner == 0
        }
    }

    /// The score before a round's `points` went to `guesserIsMe`'s side, with
    /// `counted` of them counted back up, for the reveal.
    func counting(points: Int, counted: Int, guesserIsMe: Bool) -> GuessMySpotScore {
        let held = max(0, points - counted)
        switch self {
        case let .together(total):
            return .together(total: max(0, total - held))
        case let .against(mine, partner):
            return guesserIsMe
                ? .against(mine: max(0, mine - held), partner: partner)
                : .against(mine: mine, partner: max(0, partner - held))
        }
    }
}
