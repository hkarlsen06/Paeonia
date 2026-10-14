/// Player one started the game and always moves first.
nonisolated enum BoardPlayer: Int, Codable, Hashable, Sendable {
    case one = 1
    case two = 2

    var other: BoardPlayer {
        self == .one ? .two : .one
    }
}

/// A finished game. `winner` is nil for a draw. `line` lists the board indexes
/// to highlight in ascending order, and is empty for a draw.
nonisolated struct BoardOutcome: Equatable, Hashable, Sendable {
    let winner: BoardPlayer?
    let line: [Int]
}

/// The rules of a two-player board game, played one integer move at a time.
/// The server runs the same rules, so the phone can show a move at once and
/// queue it offline. A move the rules call illegal must never reach the server.
nonisolated protocol BoardGameRules: Equatable, Sendable {
    /// Moves are integers in `0..<moveLimit`.
    static var moveLimit: Int { get }
    /// The empty board before the first move.
    static var initial: Self { get }
    /// Who moves next. Meaningless once `outcome` is set.
    var next: BoardPlayer { get }
    var outcome: BoardOutcome? { get }
    /// The board after `next` makes `move`, or nil when the move is illegal.
    func applying(_ move: Int) -> Self?
}

nonisolated extension BoardGameRules {
    func isLegal(_ move: Int) -> Bool {
        applying(move) != nil
    }

    /// Replays a whole game from the empty board. Nil if any move is illegal.
    static func replay(_ moves: [Int]) -> Self? {
        var board = initial
        for move in moves {
            guard let after = board.applying(move) else { return nil }
            board = after
        }
        return board
    }

    /// Who made each move, in order. Dots and Boxes can give a player two moves
    /// in a row. Nil if any move is illegal.
    static func movers(_ moves: [Int]) -> [BoardPlayer]? {
        var board = initial
        var players: [BoardPlayer] = []
        players.reserveCapacity(moves.count)
        for move in moves {
            guard let after = board.applying(move) else { return nil }
            players.append(board.next)
            board = after
        }
        return players
    }
}
