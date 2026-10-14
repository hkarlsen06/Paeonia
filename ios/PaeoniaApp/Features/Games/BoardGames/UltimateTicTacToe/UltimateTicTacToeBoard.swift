/// Ultimate Tic-Tac-Toe: nine small boards in a 3 by 3 grid. A move is a cell
/// index, `board * 9 + cell`, where both numbers run row by row.
///
/// The cell you play decides which small board your opponent plays in next. If
/// that board is already won or full, the opponent may play in any open board.
nonisolated struct UltimateTicTacToeBoard: BoardGameRules {
    enum SmallBoard: Equatable, Hashable, Sendable {
        case open
        case won(BoardPlayer)
        /// All nine cells are filled and nobody has three in a row.
        case full
    }

    /// The eight lines of a 3 by 3 grid, for cells in a small board and for the
    /// small boards in the big board.
    static let winningLines = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6]
    ]

    static let moveLimit = 81
    static let initial = UltimateTicTacToeBoard(
        cells: Array(repeating: nil, count: moveLimit),
        boards: Array(repeating: .open, count: 9),
        forced: nil,
        next: .one,
        outcome: nil
    )

    private(set) var cells: [BoardPlayer?]
    private(set) var boards: [SmallBoard]
    /// The small board the next move must use, or nil when any open board will do.
    private(set) var forced: Int?
    private(set) var next: BoardPlayer
    private(set) var outcome: BoardOutcome?

    private init(
        cells: [BoardPlayer?],
        boards: [SmallBoard],
        forced: Int?,
        next: BoardPlayer,
        outcome: BoardOutcome?
    ) {
        self.cells = cells
        self.boards = boards
        self.forced = forced
        self.next = next
        self.outcome = outcome
    }

    /// The move that plays `cell` of small board `board`.
    static func move(board: Int, cell: Int) -> Int {
        board * 9 + cell
    }

    /// The small boards the next move may use. Empty once the game is over.
    var openBoards: [Int] {
        guard outcome == nil else { return [] }
        if let forced {
            return [forced]
        }
        return boards.indices.filter { boards[$0] == .open }
    }

    /// The global cell indexes of the three in a row that won `board`, for
    /// drawing a strike line. Empty when nobody won the board. When one move
    /// finished two lines, this is the first of them.
    func winningCells(of board: Int) -> [Int] {
        guard boards.indices.contains(board), case .won(let player) = boards[board] else { return [] }
        let line = Self.winningLines.first { $0.allSatisfy { cells[board * 9 + $0] == player } }
        return (line ?? []).map { board * 9 + $0 }
    }

    func applying(_ move: Int) -> UltimateTicTacToeBoard? {
        guard outcome == nil, (0..<Self.moveLimit).contains(move), cells[move] == nil else { return nil }
        let board = move / 9
        let cell = move % 9
        guard boards[board] == .open, forced == nil || forced == board else { return nil }
        var after = self
        after.cells[move] = next
        after.boards[board] = after.smallBoardState(board, mover: next)
        after.forced = after.boards[cell] == .open ? cell : nil
        after.next = next.other
        after.outcome = after.finalOutcome(mover: next)
        return after
    }

    private func smallBoardState(_ board: Int, mover: BoardPlayer) -> SmallBoard {
        if Self.winningLines.contains(where: { $0.allSatisfy { cells[board * 9 + $0] == mover } }) {
            return .won(mover)
        }
        return (board * 9..<board * 9 + 9).allSatisfy { cells[$0] != nil } ? .full : .open
    }

    /// A win needs three small boards in a row. A draw needs every small board
    /// decided with no such row.
    private func finalOutcome(mover: BoardPlayer) -> BoardOutcome? {
        let wins = Self.winningLines.filter { $0.allSatisfy { boards[$0] == .won(mover) } }
        if !wins.isEmpty {
            return BoardOutcome(winner: mover, line: Set(wins.joined()).sorted())
        }
        return boards.contains(.open) ? nil : BoardOutcome(winner: nil, line: [])
    }
}
