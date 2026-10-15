/// What the die on the Ludo board does. The screen sets it and the scene plays it.
nonisolated enum LudoDieState: Equatable, Sendable {
    /// Resting in `side`'s base yard, not tappable.
    case idle(side: BoardPlayer)
    /// In my base yard, bobbing gently. Throwing it rolls.
    case ready
    // swiftlint:disable enum_case_associated_values_count
    /// Thrown with `toss` and lands on `die` in `side`'s base yard. A new `token` starts a new throw.
    case rolling(die: Int, side: BoardPlayer, token: Int, toss: LudoToss)
    // swiftlint:enable enum_case_associated_values_count
    /// Settled with `die` face up in `side`'s base yard.
    case showing(die: Int, side: BoardPlayer)
}

nonisolated extension LudoDieState {
    /// Whose base yard the die is in or goes to.
    func side(me: BoardPlayer) -> BoardPlayer {
        switch self {
        case let .idle(side), let .rolling(_, side, _, _), let .showing(_, side): side
        case .ready: me
        }
    }

    /// The face the die shows or lands on, when it has one.
    var value: Int? {
        switch self {
        case let .rolling(die, _, _, _), let .showing(die, _): die
        case .idle, .ready: nil
        }
    }
}
