/// Connect Four on a 7 by 6 grid. A move is a column, 0 to 6 from the left.
/// `cells` are numbered `row * 7 + column`, and row 0 is the top row.
nonisolated struct ConnectFourBoard: BoardGameRules {
    static let columns = 7
    static let rows = 6
    static let moveLimit = columns
    static let initial = ConnectFourBoard(
        cells: Array(repeating: nil, count: columns * rows),
        next: .one,
        outcome: nil
    )

    private(set) var cells: [BoardPlayer?]
    private(set) var next: BoardPlayer
    private(set) var outcome: BoardOutcome?

    private init(cells: [BoardPlayer?], next: BoardPlayer, outcome: BoardOutcome?) {
        self.cells = cells
        self.next = next
        self.outcome = outcome
    }

    /// How many discs are on the board.
    var discCount: Int {
        cells.count { $0 != nil }
    }

    /// The row a disc dropped in `column` lands in, or nil when the column is
    /// full or does not exist.
    func landingRow(column: Int) -> Int? {
        guard (0..<Self.columns).contains(column) else { return nil }
        return (0..<Self.rows).last { cells[$0 * Self.columns + column] == nil }
    }

    func applying(_ move: Int) -> ConnectFourBoard? {
        guard outcome == nil, let row = landingRow(column: move) else { return nil }
        var board = self
        let index = row * Self.columns + move
        board.cells[index] = next
        board.next = next.other
        let line = board.winningLine(row: row, column: move, player: next)
        if !line.isEmpty {
            board.outcome = BoardOutcome(winner: next, line: line)
        } else if board.discCount == Self.columns * Self.rows {
            board.outcome = BoardOutcome(winner: nil, line: [])
        }
        return board
    }

    /// Every cell of every run of four or more through the disc just placed.
    private func winningLine(row: Int, column: Int, player: BoardPlayer) -> [Int] {
        var line = Set<Int>()
        for (rowStep, columnStep) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var run = [row * Self.columns + column]
            for sign in [1, -1] {
                var nextRow = row + sign * rowStep
                var nextColumn = column + sign * columnStep
                while (0..<Self.rows).contains(nextRow), (0..<Self.columns).contains(nextColumn),
                      cells[nextRow * Self.columns + nextColumn] == player {
                    run.append(nextRow * Self.columns + nextColumn)
                    nextRow += sign * rowStep
                    nextColumn += sign * columnStep
                }
            }
            if run.count >= 4 {
                line.formUnion(run)
            }
        }
        return line.sorted()
    }
}
