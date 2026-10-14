/// Ludo with two pawns each on the classic cross board. The server runs the
/// same rules in `backend/convex/lib/ludo.ts`, and both have the same fixture
/// games. The rules are in `docs/games/ludo.md`.
///
/// Each pawn has a progress. 0 is the base, 1 to 51 is the shared track at
/// square `(start + progress - 1) % 52`, 52 to 56 is the pawn's own home column
/// and 57 is home. A move is `(die - 1) * 3 + choice`: the roll is part of the
/// move, so the rules use no randomness.
nonisolated struct LudoBoard: BoardGameRules {
    static let pawnsPerPlayer = 2
    static let homeProgress = 57
    static let trackLength = 52
    /// The last progress on the shared track. Progress 52 to 56 is the home column.
    static let lastTrackProgress = 51
    static let dieFaces = 6
    static let moveLimit = dieFaces * 3
    /// The four start squares and the square 8 past each. A pawn on one can't be sent home.
    static let safeSquares: Set<Int> = [0, 8, 13, 21, 26, 34, 39, 47]
    static let initial = LudoBoard(
        progress: Array(repeating: 0, count: pawnsPerPlayer * 2),
        next: .one,
        outcome: nil
    )

    /// Progress 0...57 per pawn. Player one's pawns are 0 and 1, player two's are 2 and 3.
    let progress: [Int]
    /// Who rolls next. After a 6, a capture or a pawn reaching home it is the mover again.
    let next: BoardPlayer
    let outcome: BoardOutcome?

    static func startSquare(of player: BoardPlayer) -> Int {
        player == .one ? 0 : trackLength / 2
    }

    static func pawnIndex(_ player: BoardPlayer, _ pawn: Int) -> Int {
        (player.rawValue - 1) * pawnsPerPlayer + pawn
    }

    /// The track square for a progress of 1 to 51, or nil when the pawn is in the base, a home column or home.
    static func trackSquare(of player: BoardPlayer, progress: Int) -> Int? {
        guard (1...lastTrackProgress).contains(progress) else { return nil }
        return (startSquare(of: player) + progress - 1) % trackLength
    }

    static func move(die: Int, choice: LudoChoice) -> Int {
        (die - 1) * 3 + choice.rawValue
    }

    /// The die and choice inside a move, or nil when `move` is not in `0..<18`.
    static func decode(_ move: Int) -> (die: Int, choice: LudoChoice)? {
        guard (0..<moveLimit).contains(move), let choice = LudoChoice(rawValue: move % 3) else { return nil }
        return (move / 3 + 1, choice)
    }

    /// Whether a pawn at `progress` can move by `die`. A pawn in the base needs
    /// a 6, and a pawn needs the exact number to reach home.
    static func canMove(progress: Int, die: Int) -> Bool {
        progress == 0 ? die == dieFaces : progress + die <= homeProgress
    }

    /// The moves `next` can make with `die`: the movable pawns, or `[.pass]`.
    /// Empty once the game is over. Two pawns on one square both appear.
    func legalChoices(die: Int) -> [LudoChoice] {
        guard outcome == nil else { return [] }
        let movable = [LudoChoice.first, .second].filter {
            Self.canMove(progress: progress[Self.pawnIndex(next, $0.rawValue)], die: die)
        }
        return movable.isEmpty ? [.pass] : movable
    }

    func applying(_ move: Int) -> LudoBoard? {
        resolve(move)?.board
    }
}
