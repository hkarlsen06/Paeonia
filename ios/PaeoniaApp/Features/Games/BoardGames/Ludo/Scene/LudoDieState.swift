/// What the die on the Ludo board does. The screen sets it and the scene plays it.
nonisolated enum LudoDieState: Equatable, Sendable {
    /// Resting in `side`'s base yard, not tappable.
    case idle(side: BoardPlayer)
    /// In my base yard, bobbing gently. A tap rolls.
    case ready
    /// Tumbles to `die` in `side`'s base yard. A new `token` starts a new tumble.
    case rolling(die: Int, side: BoardPlayer, token: Int)
    /// Settled with `die` face up in `side`'s base yard.
    case showing(die: Int, side: BoardPlayer)
}

nonisolated extension LudoDieState {
    /// Whose base yard the die is in or goes to.
    func side(me: BoardPlayer) -> BoardPlayer {
        switch self {
        case let .idle(side), let .rolling(_, side, _), let .showing(_, side): side
        case .ready: me
        }
    }

    /// The face the die shows or lands on, when it has one.
    var value: Int? {
        switch self {
        case let .rolling(die, _, _), let .showing(die, _): die
        case .idle, .ready: nil
        }
    }
}
