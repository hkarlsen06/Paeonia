import Foundation

/// The numbers on the reveal's score panel. Each column counts from `before` to
/// `after`, and `lines` say where the added points came from.
nonisolated struct DrawAndGuessRevealScore: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case word
            case speedBonus
            case firstTry
            case drawing
        }

        let kind: Kind
        let points: Int
    }

    struct Column: Equatable, Sendable {
        let before: Int
        let after: Int
        let lines: [Line]

        var added: Int { after - before }
    }

    enum Style: Equatable, Sendable {
        /// One total for the couple.
        case together(Column)
        case against(mine: Column, partner: Column)
    }

    let style: Style

    /// The most points one column gained.
    var largestGain: Int {
        switch style {
        case let .together(column): column.added
        case let .against(mine, theirs): max(mine.added, theirs.added)
        }
    }

    /// The result only exists on this phone, so the bonuses are the phone's own numbers.
    let isEstimate: Bool

    /// - Parameters:
    ///   - score: The totals as the cache has them.
    ///   - iAmGuesser: The guesser earns the speed bonus. The drawer earns the word's points.
    /// - Returns: Nil for a round that gave no points.
    static func make(reveal: DrawAndGuessReveal, score: DrawAndGuessScore, iAmGuesser: Bool) -> Self? {
        guard reveal.isSolved else { return nil }
        let bonus = reveal.speedBonus
        let firstTry = reveal.firstTryBonus
        let word = Line(kind: .word, points: reveal.wordPoints)
        let speed = bonus > 0 ? [Line(kind: .speedBonus, points: bonus)] : []
        let first = firstTry > 0 ? [Line(kind: .firstTry, points: firstTry)] : []
        let drawing = Line(kind: .drawing, points: reveal.wordPoints)
        // A confirmed result is already in the totals. A result still on the phone is not.
        func column(total: Int, added: Int, lines: [Line]) -> Column {
            Column(
                before: reveal.isConfirmed ? total - added : total,
                after: reveal.isConfirmed ? total : total + added,
                lines: lines
            )
        }
        let style: Style
        switch score {
        case let .together(total):
            style = .together(column(total: total, added: reveal.wordPoints, lines: [word]))
        case let .against(mine, partner):
            let guesserLines = [word] + speed + first
            let guesserAdded = reveal.wordPoints + bonus + firstTry
            style = .against(
                mine: column(
                    total: mine,
                    added: iAmGuesser ? guesserAdded : reveal.wordPoints,
                    lines: iAmGuesser ? guesserLines : [drawing]
                ),
                partner: column(
                    total: partner,
                    added: iAmGuesser ? reveal.wordPoints : guesserAdded,
                    lines: iAmGuesser ? [drawing] : guesserLines
                )
            )
        }
        return Self(style: style, isEstimate: !reveal.isConfirmed)
    }
}

/// The speed bonus of the guess in front of the player, "Against each other" only.
/// A correct guess within 15 seconds of the first look earns 2 points, within 30
/// seconds earns 1, and later earns nothing.
nonisolated enum DrawAndGuessSpeedBonus: Equatable, Sendable {
    case hidden
    /// The guesser has not seen the drawing yet. Any guess earns the full bonus.
    case open
    /// The clock runs from `startedAt`, while the partner draws live too.
    case counting(startedAt: Date)

    /// The first tier ends here. It earns `fastPoints`.
    static let fastWindow: TimeInterval = 15
    /// The last tier ends here. It earns `slowPoints`.
    static let window: TimeInterval = 30
    static let fastPoints = 2
    static let slowPoints = 1

    /// - Parameter firstSeenAt: When the guesser first saw the drawing, if they
    ///   did. Live, that is the drawer's first stroke.
    static func make(
        playStyle: GamePlayStyle?,
        round: DrawAndGuessRoundView?,
        userID: UUID?,
        firstSeenAt: Date?
    ) -> Self {
        guard playStyle == .against, let round, round.guesserUserID == userID, !round.isFinished else {
            return .hidden
        }
        guard let firstSeenAt else { return .open }
        return .counting(startedAt: firstSeenAt)
    }

    /// Seconds left of the 30, or nil when the bonus has no countdown. Zero once it is over.
    func remaining(at now: Date) -> TimeInterval? {
        guard case let .counting(startedAt) = self else { return nil }
        return max(0, Self.window - now.timeIntervalSince(startedAt))
    }

    /// The points a correct guess earns right now: 2, 1 or 0.
    func tier(at now: Date) -> Int {
        switch self {
        case .hidden:
            return 0
        case .open:
            return Self.fastPoints
        case let .counting(startedAt):
            let elapsed = now.timeIntervalSince(startedAt)
            if elapsed <= Self.fastWindow { return Self.fastPoints }
            return elapsed <= Self.window ? Self.slowPoints : 0
        }
    }

    func isAvailable(at now: Date) -> Bool {
        tier(at: now) > 0
    }
}
