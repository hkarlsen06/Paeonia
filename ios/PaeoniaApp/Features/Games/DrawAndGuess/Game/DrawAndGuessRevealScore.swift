import Foundation

/// The numbers on the reveal's score panel. Each column counts from `before` to
/// `after`, and `lines` say where the added points came from.
nonisolated struct DrawAndGuessRevealScore: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case word
            case speedBonus
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

    /// The result only exists on this phone, so the points have no speed bonus yet.
    let isEstimate: Bool

    /// - Parameters:
    ///   - score: The totals as the cache has them.
    ///   - iAmGuesser: The guesser earns the speed bonus. The drawer earns the word's points.
    /// - Returns: Nil for a round that gave no points.
    static func make(reveal: DrawAndGuessReveal, score: DrawAndGuessScore, iAmGuesser: Bool) -> Self? {
        guard reveal.isSolved else { return nil }
        let bonus = reveal.speedBonus ?? 0
        let word = Line(kind: .word, points: reveal.wordPoints)
        let speed = bonus > 0 ? [Line(kind: .speedBonus, points: bonus)] : []
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
            let guesserLines = [word] + speed
            let guesserAdded = reveal.wordPoints + bonus
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
nonisolated enum DrawAndGuessSpeedBonus: Equatable, Sendable {
    case hidden
    /// The partner is still drawing, or the guesser has not seen the finished
    /// drawing yet. Any guess earns the bonus.
    case open
    /// The 30 seconds run from `startedAt`.
    case counting(startedAt: Date)

    static let window: TimeInterval = 30

    /// - Parameter firstSeenAt: When the guesser first saw the drawing, if they did.
    static func make(
        playStyle: GamePlayStyle?,
        round: DrawAndGuessRoundView?,
        userID: UUID?,
        firstSeenAt: Date?
    ) -> Self {
        guard playStyle == .against, let round, round.guesserUserID == userID, !round.isFinished else {
            return .hidden
        }
        guard round.isDrawingSent, let firstSeenAt else {
            return .open
        }
        // The clock starts when both the drawing and the guesser are there.
        return .counting(startedAt: max(firstSeenAt, round.drawingSubmittedAt ?? firstSeenAt))
    }

    /// Seconds left, or nil when the bonus has no countdown. Zero once it is over.
    func remaining(at now: Date) -> TimeInterval? {
        guard case let .counting(startedAt) = self else { return nil }
        return max(0, Self.window - now.timeIntervalSince(startedAt))
    }

    func isAvailable(at now: Date) -> Bool {
        switch self {
        case .hidden: false
        case .open: true
        case .counting: (remaining(at: now) ?? 0) > 0
        }
    }
}
