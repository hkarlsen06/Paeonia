/// Which pawn a move uses. `pass` is the move when no pawn can move.
nonisolated enum LudoChoice: Int, Sendable {
    case first = 0
    case second = 1
    case pass = 2
}

/// A place a pawn can stand.
nonisolated enum LudoSquare: Equatable, Sendable {
    case base(BoardPlayer, slot: Int)
    /// A square of the shared track, 0...51.
    case track(Int)
    /// A square of the player's own home column, step 1...5.
    case homeColumn(BoardPlayer, step: Int)
    case home(BoardPlayer)
}

/// What one move does, for animation.
nonisolated struct LudoTransition: Equatable, Sendable {
    let player: BoardPlayer
    let die: Int
    let choice: LudoChoice
    /// The pawn that moved, as a `pawnIndex`. Nil for a pass.
    let pawn: Int?
    /// Every square the pawn steps on in order, the last one included. Empty for a pass.
    let path: [LudoSquare]
    /// Partner pawns sent back to their base, as pawn indexes in ascending order.
    let sentHome: [Int]
    /// Whether the same player rolls again. False when the move ends the game.
    let rollsAgain: Bool
}

nonisolated extension LudoBoard {
    /// Where the pawn with this `pawnIndex` stands. A pawn in the base has the
    /// base slot of its position among its player's pawns.
    func square(ofPawn index: Int) -> LudoSquare {
        let player: BoardPlayer = index < Self.pawnsPerPlayer ? .one : .two
        return Self.square(player: player, pawn: index % Self.pawnsPerPlayer, progress: progress[index])
    }

    /// What one move does, or nil when the move is illegal.
    func transition(_ move: Int) -> LudoTransition? {
        resolve(move)?.transition
    }

    static func square(player: BoardPlayer, pawn: Int, progress: Int) -> LudoSquare {
        if progress == 0 { return .base(player, slot: pawn) }
        if progress == homeProgress { return .home(player) }
        if let square = trackSquare(of: player, progress: progress) { return .track(square) }
        return .homeColumn(player, step: progress - lastTrackProgress)
    }

    /// The board and transition after `move`, or nil when it is illegal.
    func resolve(_ move: Int) -> (board: LudoBoard, transition: LudoTransition)? {
        guard outcome == nil,
              let (die, choice) = Self.decode(move),
              legalChoices(die: die).contains(choice) else { return nil }
        let mover = next
        var progress = progress
        var pawn: Int?
        var path: [LudoSquare] = []
        var sentHome: [Int] = []

        if choice != .pass {
            let index = Self.pawnIndex(mover, choice.rawValue)
            let from = progress[index]
            let to = from == 0 ? 1 : from + die
            progress[index] = to
            pawn = index
            path = ((from + 1)...to).map { Self.square(player: mover, pawn: choice.rawValue, progress: $0) }
            sentHome = pawnsSentHome(
                byLandingOn: Self.trackSquare(of: mover, progress: to),
                partner: mover.other,
                in: progress
            )
            sentHome.forEach { progress[$0] = 0 }
        }

        let won = (0..<Self.pawnsPerPlayer).allSatisfy { progress[Self.pawnIndex(mover, $0)] == Self.homeProgress }
        let reachedHome = pawn.map { progress[$0] == Self.homeProgress } ?? false
        let rollsAgain = !won && (die == Self.dieFaces || !sentHome.isEmpty || reachedHome)
        let board = LudoBoard(
            progress: progress,
            next: rollsAgain || won ? mover : mover.other,
            outcome: won ? BoardOutcome(winner: mover, line: []) : nil
        )
        let transition = LudoTransition(
            player: mover,
            die: die,
            choice: choice,
            pawn: pawn,
            path: path,
            sentHome: sentHome,
            rollsAgain: rollsAgain
        )
        return (board, transition)
    }

    /// The partner pawns a pawn landing on `square` sends home. That is every partner pawn on the track
    /// square, unless the square is safe.
    private func pawnsSentHome(byLandingOn square: Int?, partner: BoardPlayer, in progress: [Int]) -> [Int] {
        guard let square, !Self.safeSquares.contains(square) else { return [] }
        return (0..<Self.pawnsPerPlayer)
            .map { Self.pawnIndex(partner, $0) }
            .filter { Self.trackSquare(of: partner, progress: progress[$0]) == square }
    }
}
