import CoreGraphics

/// Where everything sits on an Ultimate Tic-Tac-Toe board, in the board's own
/// coordinates (origin top left, y down), and which board and cell a point hits.
/// It is pure, so the layout, the zoom transform and the hit tests run in tests
/// without a screen.
nonisolated struct UltimateTicTacToeBoardGeometry: Equatable {
    /// The empty edge around the nine small boards, as a fraction of the side.
    static let marginFraction: CGFloat = 0.015
    /// The gap between neighboring small boards, as a fraction of the side.
    static let gapFraction: CGFloat = 0.04
    /// How much of the view a focused small board fills.
    static let focusFill: CGFloat = 0.9
    /// How far past its edge the view draws, as a fraction of the side, so the
    /// glow and pulse of an edge board are not cut off. A focused board's
    /// neighbors start about 0.07 of the side past the edge, so they stay hidden.
    static let glowBleedFraction: CGFloat = 0.05

    let side: CGFloat

    var margin: CGFloat { side * Self.marginFraction }
    var glowBleed: CGFloat { side * Self.glowBleedFraction }
    var gap: CGFloat { side * Self.gapFraction }
    var smallSide: CGFloat { (side - 2 * margin - 2 * gap) / 3 }
    var small: UltimateTicTacToeSmallBoardGeometry { UltimateTicTacToeSmallBoardGeometry(side: smallSide) }

    private var pitch: CGFloat { smallSide + gap }

    func smallRect(_ board: Int) -> CGRect {
        CGRect(
            x: margin + CGFloat(board % 3) * pitch,
            y: margin + CGFloat(board / 3) * pitch,
            width: smallSide,
            height: smallSide
        )
    }

    func center(of board: Int) -> CGPoint {
        let rect = smallRect(board)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// A cell's drawn area in board coordinates.
    func cellRect(board: Int, cell: Int) -> CGRect {
        let origin = smallRect(board).origin
        return small.cellRect(cell).offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: Hit tests

    /// The small board nearest to a point. Each axis switches boards in the
    /// middle of a gap, so every point on the board belongs to exactly one.
    func nearestBoard(to point: CGPoint) -> Int {
        band(point.y) * 3 + band(point.x)
    }

    /// The cell of `board` a point falls in. The board splits into thirds with
    /// no padding, and points outside it count as the nearest edge cell.
    func cell(in board: Int, at point: CGPoint) -> Int {
        let origin = smallRect(board).origin
        return small.cell(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
    }

    /// The move a point stands for: the nearest board, then the cell under it.
    /// Without the zoom (VoiceOver) a tap plays this directly, so every point of
    /// the board is a cell.
    func move(at point: CGPoint) -> Int {
        let board = nearestBoard(to: point)
        return UltimateTicTacToeBoard.move(board: board, cell: cell(in: board, at: point))
    }

    private func band(_ value: CGFloat) -> Int {
        guard pitch > 0 else { return 0 }
        let band = ((value - margin + gap / 2) / pitch).rounded(.down)
        return Int(min(max(band, 0), 2))
    }

    // MARK: Zoom

    /// The transform that puts `board` in the middle of the view, filling
    /// `focusFill` of its width. Nil shows the whole board.
    func transform(focusing board: Int?) -> UltimateTicTacToeViewTransform {
        guard let board, smallSide > 0 else { return .identity }
        let rect = smallRect(board)
        let scale = Self.focusFill * side / rect.width
        return UltimateTicTacToeViewTransform(
            scale: scale,
            translation: CGSize(width: side / 2 - rect.midX * scale, height: side / 2 - rect.midY * scale)
        )
    }

    // MARK: Outcome line

    /// The ends of the line through a row of small boards, which are the centers
    /// of the first and the last board.
    func lineEnds(through boards: [Int]) -> (start: CGPoint, end: CGPoint)? {
        guard let first = boards.first, let last = boards.last else { return nil }
        return (center(of: first), center(of: last))
    }

    func lineMidpoint(through boards: [Int]) -> CGPoint? {
        guard let ends = lineEnds(through: boards) else { return nil }
        return CGPoint(x: (ends.start.x + ends.end.x) / 2, y: (ends.start.y + ends.end.y) / 2)
    }
}

/// The layout inside one small board, in the small board's own coordinates.
nonisolated struct UltimateTicTacToeSmallBoardGeometry: Equatable {
    /// Space between the board's edge and its cells, as a fraction of its side.
    static let insetFraction: CGFloat = 0.06

    let side: CGFloat

    var inset: CGFloat { side * Self.insetFraction }
    var cellSide: CGFloat { (side - 2 * inset) / 3 }

    func cellRect(_ cell: Int) -> CGRect {
        CGRect(
            x: inset + CGFloat(cell % 3) * cellSide,
            y: inset + CGFloat(cell / 3) * cellSide,
            width: cellSide,
            height: cellSide
        )
    }

    func cellCenter(_ cell: Int) -> CGPoint {
        let rect = cellRect(cell)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// The area a tap on this cell may land in: a third of the board, with no
    /// padding, so a tap never falls between cells.
    func hitRect(_ cell: Int) -> CGRect {
        CGRect(x: CGFloat(cell % 3) * side / 3, y: CGFloat(cell / 3) * side / 3, width: side / 3, height: side / 3)
    }

    func cell(at point: CGPoint) -> Int {
        guard side > 0 else { return 0 }
        let column = min(max((point.x / side * 3).rounded(.down), 0), 2)
        let row = min(max((point.y / side * 3).rounded(.down), 0), 2)
        return Int(row) * 3 + Int(column)
    }

    /// The ends of a strike line through three cells in a row. It runs a little
    /// past the first and last cell center.
    func strikeLine(through cells: [Int]) -> (start: CGPoint, end: CGPoint)? {
        guard cells.count >= 2, let first = cells.first, let last = cells.last else { return nil }
        let start = cellCenter(first)
        let end = cellCenter(last)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        let extra = cellSide * 0.28 / length
        return (
            CGPoint(x: start.x - dx * extra, y: start.y - dy * extra),
            CGPoint(x: end.x + dx * extra, y: end.y + dy * extra)
        )
    }
}

/// A scale and a shift that map board coordinates to view coordinates:
/// `view = board * scale + translation`. It matches `scaleEffect(_, anchor:
/// .topLeading)` followed by `offset`.
nonisolated struct UltimateTicTacToeViewTransform: Equatable {
    var scale: CGFloat
    var translation: CGSize

    static let identity = UltimateTicTacToeViewTransform(scale: 1, translation: .zero)

    func apply(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + translation.width, y: point.y * scale + translation.height)
    }

    func invert(_ point: CGPoint) -> CGPoint {
        guard scale != 0 else { return point }
        return CGPoint(x: (point.x - translation.width) / scale, y: (point.y - translation.height) / scale)
    }
}
