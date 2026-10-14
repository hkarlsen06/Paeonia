import CoreGraphics

/// Where everything sits on a Connect Four board, worked out from the width the
/// board is given. Above the board is a lane one cell tall for the hovering disc.
/// The board face is 7 cells wide and 6 tall plus a frame, so the lane and the
/// board together fill a square.
///
/// Points are in the view's own coordinates, with the origin at the top left of
/// the lane. Cell numbers match `ConnectFourBoard.cells`: `row * 7 + column`, and
/// row 0 is the top row.
nonisolated struct ConnectFourBoardGeometry: Equatable {
    static let columns = ConnectFourBoard.columns
    static let rows = ConnectFourBoard.rows
    /// The widest the board grows unless the screen asks for more, in points.
    static let defaultMaxWidth: CGFloat = 560
    /// The frame around the holes, as a fraction of a cell.
    static let frameRatio: CGFloat = 0.16
    private static let holeRatio: CGFloat = 0.8
    /// Discs are a little wider than the holes, so no edge shows between a disc and the face.
    private static let discOversize: CGFloat = 1.04

    let width: CGFloat

    init(width: CGFloat) {
        self.width = max(0, width)
    }

    var cell: CGFloat { width / (CGFloat(Self.columns) + 2 * Self.frameRatio) }
    var inset: CGFloat { cell * Self.frameRatio }
    var holeDiameter: CGFloat { cell * Self.holeRatio }
    var discDiameter: CGFloat { holeDiameter * Self.discOversize }
    var laneHeight: CGFloat { cell }
    var boardHeight: CGFloat { CGFloat(Self.rows) * cell + 2 * inset }
    var totalHeight: CGFloat { laneHeight + boardHeight }

    // MARK: Points

    func columnCenterX(_ column: Int) -> CGFloat {
        inset + (CGFloat(column) + 0.5) * cell
    }

    func cellCenter(row: Int, column: Int) -> CGPoint {
        CGPoint(x: columnCenterX(column), y: laneHeight + inset + (CGFloat(row) + 0.5) * cell)
    }

    func cellCenter(index: Int) -> CGPoint {
        cellCenter(row: index / Self.columns, column: index % Self.columns)
    }

    /// Where a hovering disc sits above a column.
    func hoverCenter(column: Int) -> CGPoint {
        CGPoint(x: columnCenterX(column), y: laneHeight / 2)
    }

    /// A hole's square in the board face's own coordinates, with the origin at
    /// the top left of the face (just below the lane).
    func holeRect(row: Int, column: Int) -> CGRect {
        let center = cellCenter(row: row, column: column)
        return CGRect(
            x: center.x - holeDiameter / 2,
            y: center.y - laneHeight - holeDiameter / 2,
            width: holeDiameter,
            height: holeDiameter
        )
    }

    /// The column under a horizontal position. A position left or right of the
    /// board picks the first or last column.
    func column(forX x: CGFloat) -> Int {
        guard cell > 0 else { return 0 }
        let raw = ((x - inset) / cell).rounded(.down)
        return Int(min(max(raw, 0), CGFloat(Self.columns - 1)))
    }

    /// The middle of the box around a set of cells, for the petal bloom.
    func middle(of cells: [Int]) -> CGPoint {
        let centers = cells.map { cellCenter(index: $0) }
        guard let minX = centers.map(\.x).min(), let maxX = centers.map(\.x).max(),
              let minY = centers.map(\.y).min(), let maxY = centers.map(\.y).max()
        else {
            return CGPoint(x: width / 2, y: laneHeight + boardHeight / 2)
        }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    /// How far a disc falls from the hover lane to the middle of a row, in cells.
    static func dropDistance(toRow row: Int) -> Double {
        1 + Double(frameRatio) + Double(row)
    }

    // MARK: Winning runs

    static func cellIndex(row: Int, column: Int) -> Int? {
        guard (0..<rows).contains(row), (0..<columns).contains(column) else { return nil }
        return row * columns + column
    }

    /// The runs of four or more inside a winning line, each in order along its
    /// direction. Two runs through one disc, or a run of five, show as one
    /// glowing line per run.
    static func runs(in line: [Int]) -> [[Int]] {
        let members = Set(line)
        var result: [[Int]] = []
        for (rowStep, columnStep) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            for index in line.sorted() {
                let row = index / columns
                let column = index % columns
                // Start only at the beginning of a run.
                let before = cellIndex(row: row - rowStep, column: column - columnStep)
                if let before, members.contains(before) {
                    continue
                }
                var run = [index]
                var nextRow = row + rowStep
                var nextColumn = column + columnStep
                while let next = cellIndex(row: nextRow, column: nextColumn), members.contains(next) {
                    run.append(next)
                    nextRow += rowStep
                    nextColumn += columnStep
                }
                if run.count >= 4 {
                    result.append(run)
                }
            }
        }
        return result
    }
}

nonisolated extension ConnectFourBoard {
    /// The index of the highest disc in a column, or nil for an empty column or
    /// a column that does not exist.
    func topDiscIndex(column: Int) -> Int? {
        guard (0..<Self.columns).contains(column) else { return nil }
        return (0..<Self.rows).map { $0 * Self.columns + column }.first { cells[$0] != nil }
    }

    func discCount(inColumn column: Int) -> Int {
        guard (0..<Self.columns).contains(column) else { return 0 }
        return (0..<Self.rows).count { cells[$0 * Self.columns + column] != nil }
    }
}
