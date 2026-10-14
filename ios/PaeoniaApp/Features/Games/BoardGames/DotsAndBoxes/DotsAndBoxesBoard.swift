/// Dots and Boxes on 5 by 5 dots, which makes 4 by 4 boxes and 40 lines. A move
/// is a line index.
///
/// Horizontal line `h(row, column)` is `row * 4 + column`, for dot rows 0 to 4
/// and columns 0 to 3, so indexes 0 to 19. Vertical line `v(row, column)` is
/// `20 + row * 5 + column`, for rows 0 to 3 and dot columns 0 to 4, so indexes
/// 20 to 39. Box `row * 4 + column` has `h(row, column)` on top,
/// `h(row + 1, column)` below, `v(row, column)` on the left and
/// `v(row, column + 1)` on the right.
nonisolated struct DotsAndBoxesBoard: BoardGameRules {
    /// Where a line sits on the grid of dots.
    struct LinePosition: Equatable, Hashable, Sendable {
        let isHorizontal: Bool
        /// The dot row for a horizontal line, the box row for a vertical one.
        let row: Int
        /// The box column for a horizontal line, the dot column for a vertical one.
        let column: Int
    }

    static let boxesPerSide = 4
    static let horizontalLineCount = 20
    static let moveLimit = 40
    static let boxTotal = 16
    static let initial = DotsAndBoxesBoard(
        lines: Array(repeating: nil, count: moveLimit),
        boxes: Array(repeating: nil, count: boxTotal),
        next: .one,
        outcome: nil
    )

    /// Who drew each line, or nil while it is open.
    private(set) var lines: [BoardPlayer?]
    /// Who closed each box, or nil while it is open.
    private(set) var boxes: [BoardPlayer?]
    private(set) var next: BoardPlayer
    private(set) var outcome: BoardOutcome?

    private init(lines: [BoardPlayer?], boxes: [BoardPlayer?], next: BoardPlayer, outcome: BoardOutcome?) {
        self.lines = lines
        self.boxes = boxes
        self.next = next
        self.outcome = outcome
    }

    static func horizontalLine(row: Int, column: Int) -> Int {
        row * boxesPerSide + column
    }

    static func verticalLine(row: Int, column: Int) -> Int {
        horizontalLineCount + row * (boxesPerSide + 1) + column
    }

    /// Decodes a line index for drawing. Nil when the index is not a line.
    static func position(of line: Int) -> LinePosition? {
        guard (0..<moveLimit).contains(line) else { return nil }
        if line < horizontalLineCount {
            return LinePosition(isHorizontal: true, row: line / boxesPerSide, column: line % boxesPerSide)
        }
        let offset = line - horizontalLineCount
        return LinePosition(isHorizontal: false, row: offset / (boxesPerSide + 1), column: offset % (boxesPerSide + 1))
    }

    /// The boxes a line borders, in ascending order. Border lines touch one box.
    static func boxes(touching line: Int) -> [Int] {
        guard let position = position(of: line) else { return [] }
        let side = boxesPerSide
        let touching: [(row: Int, column: Int)] = position.isHorizontal
            ? [(position.row - 1, position.column), (position.row, position.column)]
            : [(position.row, position.column - 1), (position.row, position.column)]
        return touching
            .filter { (0..<side).contains($0.row) && (0..<side).contains($0.column) }
            .map { $0.row * side + $0.column }
    }

    /// The four lines around a box: top, bottom, left, right.
    static func lines(of box: Int) -> [Int] {
        let row = box / boxesPerSide
        let column = box % boxesPerSide
        return [
            horizontalLine(row: row, column: column),
            horizontalLine(row: row + 1, column: column),
            verticalLine(row: row, column: column),
            verticalLine(row: row, column: column + 1)
        ]
    }

    func boxCount(for player: BoardPlayer) -> Int {
        boxes.count { $0 == player }
    }

    func applying(_ move: Int) -> DotsAndBoxesBoard? {
        guard outcome == nil, (0..<Self.moveLimit).contains(move), lines[move] == nil else { return nil }
        var board = self
        board.lines[move] = next
        let closed = Self.boxes(touching: move).filter { box in
            Self.lines(of: box).allSatisfy { board.lines[$0] != nil }
        }
        for box in closed {
            board.boxes[box] = next
        }
        // Closing a box earns another line. Otherwise the turn passes.
        if closed.isEmpty {
            board.next = next.other
        }
        if board.lines.allSatisfy({ $0 != nil }) {
            board.outcome = board.finalOutcome()
        }
        return board
    }

    private func finalOutcome() -> BoardOutcome {
        let one = boxCount(for: .one)
        let two = boxCount(for: .two)
        guard one != two else { return BoardOutcome(winner: nil, line: []) }
        let winner: BoardPlayer = one > two ? .one : .two
        return BoardOutcome(winner: winner, line: boxes.indices.filter { boxes[$0] == winner })
    }
}
