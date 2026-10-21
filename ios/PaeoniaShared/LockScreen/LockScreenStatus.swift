import Foundation

/// The streak widgets. The ring has a left half for this person and a right
/// half for the partner. When both are active it is one closed circle.
nonisolated struct LockScreenStreak: Equatable, Sendable {
    enum Ring: Equatable, Sendable {
        case neither
        case me
        case partner
        case both

        init(meActive: Bool, partnerActive: Bool) {
            switch (meActive, partnerActive) {
            case (true, true): self = .both
            case (true, false): self = .me
            case (false, true): self = .partner
            case (false, false): self = .neither
            }
        }

        /// A piece of the ring as fractions of a full turn, clockwise from 12 o'clock.
        struct Arc: Equatable, Sendable {
            let start: Double
            let end: Double
        }

        /// Two halves with a small gap between them, or one full circle when both are active.
        var arcs: [Arc] {
            let gap = 0.02
            switch self {
            case .neither: return []
            case .me: return [Arc(start: 0.5 + gap, end: 1 - gap)]
            case .partner: return [Arc(start: gap, end: 0.5 - gap)]
            case .both: return [Arc(start: 0, end: 1)]
            }
        }
    }

    let count: Int
    let ring: Ring

    /// After the couple's day ends, nobody has been active yet in the new day.
    init?(_ snapshot: LockScreenSnapshot, at date: Date) {
        guard let streak = snapshot.streak else { return nil }
        let isToday = snapshot.isInCoupleDay(at: date)
        count = streak.currentCount
        ring = Ring(
            meActive: isToday && streak.meActiveToday,
            partnerActive: isToday && streak.partnerActiveToday
        )
    }
}

/// The today's question widgets. They say who has answered, never what.
nonisolated enum LockScreenQuestionState: Equatable, Sendable {
    case waiting
    case partnerAnswered
    case waitingForPartner
    case bothAnswered

    init(meAnswered: Bool, partnerAnswered: Bool) {
        switch (meAnswered, partnerAnswered) {
        case (true, true): self = .bothAnswered
        case (true, false): self = .waitingForPartner
        case (false, true): self = .partnerAnswered
        case (false, false): self = .waiting
        }
    }

    var meAnswered: Bool { self == .waitingForPartner || self == .bothAnswered }
    var partnerAnswered: Bool { self == .partnerAnswered || self == .bothAnswered }

    /// After the couple's day ends, the new question has no answers yet.
    init?(_ snapshot: LockScreenSnapshot, at date: Date) {
        guard let question = snapshot.dailyQuestion else { return nil }
        let isToday = snapshot.isInCoupleDay(at: date)
        self.init(
            meAnswered: isToday && question.meAnswered,
            partnerAnswered: isToday && question.partnerAnswered
        )
    }
}

/// The "Your move" widget.
nonisolated struct LockScreenYourMove: Equatable, Sendable {
    let turnCount: Int
    /// The `GameKind` raw value of the first game waiting, such as `draw_and_guess`.
    let firstGameKind: String?

    var isMyTurn: Bool { turnCount > 0 }

    /// A count to show next to the symbol, only when more than one game waits.
    var badgeCount: Int? { turnCount > 1 ? turnCount : nil }

    /// The `paeonia://games/<path>` path. Game paths use hyphens where kinds use underscores.
    var gamePath: String? {
        guard isMyTurn, let firstGameKind, !firstGameKind.isEmpty else { return nil }
        return firstGameKind.replacingOccurrences(of: "_", with: "-")
    }

    init(_ games: LockScreenSnapshot.Games) {
        turnCount = max(0, games.myTurnCount)
        firstGameKind = games.firstMyTurnKind
    }
}
