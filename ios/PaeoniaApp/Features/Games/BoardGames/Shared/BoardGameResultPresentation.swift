import SwiftUI

/// A tally that counts from `before` to `after`.
nonisolated struct BoardGameCount: Equatable, Sendable {
    let before: Int
    let after: Int

    var added: Int { after - before }

    /// A number that stays as it is.
    static func settled(_ value: Int) -> BoardGameCount {
        BoardGameCount(before: value, after: value)
    }

    /// A number that went up by one to reach `value`.
    static func counting(to value: Int) -> BoardGameCount {
        BoardGameCount(before: max(0, value - 1), after: value)
    }
}

/// What the result panel counts and says. The content holds the tallies after
/// the game, so the panel works out where each count starts.
extension BoardGameResultContent {
    /// My wins. They count up when I won.
    var myCount: BoardGameCount {
        winner == .me ? .counting(to: myWins) : .settled(myWins)
    }

    var partnerCount: BoardGameCount {
        winner == .partner ? .counting(to: partnerWins) : .settled(partnerWins)
    }

    /// The couple's finished games, which every game adds to, a draw too.
    var gamesCount: BoardGameCount {
        .counting(to: gamesFinished)
    }

    /// Whether any number on the panel counts up. A draw adds to no one's wins.
    var countsUp: Bool {
        playStyle == .together || winner != .draw
    }

    /// The score as the couple's play style shows it, after this game.
    var score: BoardGameScore {
        switch playStyle {
        case .against: .against(mine: myWins, partner: partnerWins)
        case .together: .together(games: gamesFinished)
        }
    }

    func title(partnerName: String) -> LocalizedStringResource {
        switch (playStyle, winner) {
        case (_, .draw): .boardGamesResultTitleDraw
        case (.against, .me): .boardGamesResultTitleYouWon
        case (.against, .partner): .boardGamesResultTitlePartnerWon(partnerName)
        case (.together, .me): .boardGamesResultTitleYouWonThis
        case (.together, .partner): .boardGamesResultTitlePartnerWonThis(partnerName)
        }
    }

    /// Who claimed the stake. Nil when the game was played for nothing.
    func stakeLine(partnerName: String) -> LocalizedStringResource? {
        guard let stake else { return nil }
        let line: LocalizedStringResource = switch winner {
        case .me: .boardGamesResultStakeYou(stake)
        case .partner: .boardGamesResultStakePartner(partnerName, stake)
        case .draw: .boardGamesResultStakeNobody(stake)
        }
        return line
    }

    /// The whole result in one sentence for VoiceOver.
    func spokenSummary(partnerName: String) -> String {
        [
            String(localized: title(partnerName: partnerName)),
            stakeLine(partnerName: partnerName).map { String(localized: $0) },
            String(localized: score.spoken(partnerName: partnerName)),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
