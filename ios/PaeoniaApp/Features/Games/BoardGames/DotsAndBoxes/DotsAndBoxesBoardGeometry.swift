import CoreGraphics

/// Where everything sits on a Dots and Boxes board that is `side` points wide.
/// All positions are in the board's own coordinate space, with the origin at the
/// top leading corner. The grid of dots sits inside an inset, so the edge dots,
/// their lines and the taps just outside them all fit in the square.
///
/// This is pure, so the tap picking and the photo pieces are tested without a view.
nonisolated struct DotsAndBoxesBoardGeometry: Equatable, Sendable {
    /// A line as the view draws it, from one dot to the next.
    struct Segment: Equatable, Sendable {
        let start: CGPoint
        let end: CGPoint
        let isHorizontal: Bool

        var midpoint: CGPoint {
            CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        }

        var length: CGFloat {
            abs(end.x - start.x) + abs(end.y - start.y)
        }
    }

    /// The widest the board grows.
    static let maxSide: CGFloat = 560
    static let dotsPerSide = DotsAndBoxesBoard.boxesPerSide + 1
    static let dotTotal = dotsPerSide * dotsPerSide
    /// How far past the board a finger can drift before the touch stops picking a line.
    static let touchSlop: CGFloat = 28

    let side: CGFloat

    // MARK: Layout

    var inset: CGFloat { side / 16 }

    /// The width of one box, which is the distance between two neighboring dots.
    var cell: CGFloat { (side - inset * 2) / CGFloat(DotsAndBoxesBoard.boxesPerSide) }

    /// The square from the first dot to the last.
    var gridRect: CGRect {
        let length = cell * CGFloat(DotsAndBoxesBoard.boxesPerSide)
        return CGRect(x: inset, y: inset, width: length, height: length)
    }

    /// The area where a touch still counts as on the board.
    var touchBounds: CGRect {
        let slop = Self.touchSlop
        return CGRect(x: -slop, y: -slop, width: side + slop * 2, height: side + slop * 2)
    }

    // MARK: Sizes

    /// About 5 points on a phone.
    var lineThickness: CGFloat { cell * 0.07 }
    var dotDiameter: CGFloat { cell * 0.105 }
    var activeDotDiameter: CGFloat { cell * 0.14 }
    var guideThickness: CGFloat { cell * 0.03 }
    /// The space between two claimed pieces while the game is on.
    var pieceGap: CGFloat { cell * 0.04 }
    var pieceCornerRadius: CGFloat { cell * 0.09 }
    /// The photo is scaled to fill this square, which is the grid of boxes.
    var photoSide: CGFloat { gridRect.width }

    // MARK: Dots, lines and boxes

    func dot(row: Int, column: Int) -> CGPoint {
        CGPoint(x: gridRect.minX + CGFloat(column) * cell, y: gridRect.minY + CGFloat(row) * cell)
    }

    /// Dots are numbered row by row, 0 to 24.
    func dotPosition(index: Int) -> CGPoint {
        dot(row: index / Self.dotsPerSide, column: index % Self.dotsPerSide)
    }

    /// The two dots a line joins, as dot indexes. Empty when the index is not a line.
    static func dotIndices(of line: Int) -> [Int] {
        guard let position = DotsAndBoxesBoard.position(of: line) else { return [] }
        let first = position.row * dotsPerSide + position.column
        let second = position.isHorizontal ? first + 1 : first + dotsPerSide
        return [first, second]
    }

    func segment(of line: Int) -> Segment? {
        guard let position = DotsAndBoxesBoard.position(of: line) else { return nil }
        let start = dot(row: position.row, column: position.column)
        let end = position.isHorizontal
            ? dot(row: position.row, column: position.column + 1)
            : dot(row: position.row + 1, column: position.column)
        return Segment(start: start, end: end, isHorizontal: position.isHorizontal)
    }

    /// The rectangle a line's view occupies. It has room around the line for the
    /// thicker stroke while the line grows.
    func frame(of segment: Segment) -> CGRect {
        let padding = lineThickness
        return CGRect(
            x: min(segment.start.x, segment.end.x) - padding,
            y: min(segment.start.y, segment.end.y) - padding,
            width: abs(segment.end.x - segment.start.x) + padding * 2,
            height: abs(segment.end.y - segment.start.y) + padding * 2
        )
    }

    /// The box between four dots, with no gap.
    func boxRect(_ box: Int) -> CGRect {
        let count = DotsAndBoxesBoard.boxesPerSide
        return CGRect(
            x: gridRect.minX + CGFloat(box % count) * cell,
            y: gridRect.minY + CGFloat(box / count) * cell,
            width: cell,
            height: cell
        )
    }

    /// A box's piece of the photo, in the photo's own coordinates. The 16 pieces
    /// tile the photo square exactly.
    func photoPieceRect(forBox box: Int) -> CGRect {
        let count = DotsAndBoxesBoard.boxesPerSide
        return CGRect(x: CGFloat(box % count) * cell, y: CGFloat(box / count) * cell, width: cell, height: cell)
    }

    // MARK: Picking

    /// The line a touch at `point` picks. Each box splits into four triangles
    /// from its center to its edges, and a triangle picks that edge's line. The
    /// two boxes that share a line give it the diamond between their centers.
    /// A point outside the grid picks as if it sat on the nearest border. Nil
    /// only when the board has no size.
    func line(at point: CGPoint) -> Int? {
        let count = DotsAndBoxesBoard.boxesPerSide
        guard cell > 0, point.x.isFinite, point.y.isFinite else { return nil }
        let x = min(max(point.x, gridRect.minX), gridRect.maxX)
        let y = min(max(point.y, gridRect.minY), gridRect.maxY)
        let column = min(Int((x - gridRect.minX) / cell), count - 1)
        let row = min(Int((y - gridRect.minY) / cell), count - 1)
        let rect = boxRect(row * count + column)
        let offsetX = x - rect.midX
        let offsetY = y - rect.midY
        if abs(offsetX) > abs(offsetY) {
            return DotsAndBoxesBoard.verticalLine(row: row, column: offsetX < 0 ? column : column + 1)
        }
        return DotsAndBoxesBoard.horizontalLine(row: offsetY < 0 ? row : row + 1, column: column)
    }

    /// The line a stroke from `start` to `end` picks. A stroke shorter than a
    /// third of a box is a tap and picks like `line(at: end)`. A longer stroke
    /// picks the line that runs the same way as the stroke and sits nearest its
    /// middle, so drawing from one dot to the next picks the line between them.
    func line(from start: CGPoint, to end: CGPoint) -> Int? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard cell > 0, length.isFinite, length >= cell / 3 else { return line(at: end) }
        let count = DotsAndBoxesBoard.boxesPerSide
        let middleX = (start.x + end.x) / 2 - gridRect.minX
        let middleY = (start.y + end.y) / 2 - gridRect.minY
        // Along the stroke the middle falls between two dots. Across it, it snaps to the nearest row of dots.
        let between = { (offset: CGFloat) in min(max(Int((offset / self.cell).rounded(.down)), 0), count - 1) }
        let nearest = { (offset: CGFloat) in min(max(Int((offset / self.cell).rounded()), 0), count) }
        if abs(dx) >= abs(dy) {
            return DotsAndBoxesBoard.horizontalLine(row: nearest(middleY), column: between(middleX))
        }
        return DotsAndBoxesBoard.verticalLine(row: between(middleY), column: nearest(middleX))
    }
}
