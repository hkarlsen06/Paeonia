import SwiftUI

/// The picture at the top of the Ultimate Tic-Tac-Toe card: the big grid of nine small
/// boards zooms into one of them, where a heart and a loop are inked in turn until three
/// hearts line up. Then the view zooms back out, a gold line strikes through the won board,
/// and the board the next player must use starts to glow. It plays once when the card
/// appears. With Reduce Motion it starts finished.
struct UltimateTicTacToeHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 7
    private static let playDelay: TimeInterval = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            sparkles(shown: shown)
            UltimateTicTacToeScene(progress: shown ? 1 : 0)
                // An even pace, so the zoom and each ink stroke can ease on their own (see `UltimateTicTacToeScene`).
                .animation(
                    reduceMotion ? nil : .linear(duration: Self.playDuration).delay(Self.playDelay),
                    value: isPlayed
                )
                .scaleEffect(shown ? 1 : 0.9)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: isPlayed)
                // Clear of the chips at the top of the card and the fade into the card at the bottom.
                .padding(.top, PaeoniaSpacing.space40)
                .padding(.bottom, PaeoniaSpacing.space32)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }

    /// A cooler mood than the other cards, blue and lavender, so the pink marks stand out.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.paeoniaInkBlue.opacity(0.32), .clear],
                center: UnitPoint(x: 0.08, y: 0.1),
                startRadius: 0,
                endRadius: 230
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.4), .clear],
                center: UnitPoint(x: 0.92, y: 0.9),
                startRadius: 0,
                endRadius: 220
            )
        }
    }

    private func sparkles(shown: Bool) -> some View {
        GeometryReader { proxy in
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                let pop = PaeoniaMotion.cardReveal.delay(
                    Self.playDelay + Self.playDuration * (0.92 + 0.025 * Double(index))
                )
                Image(systemName: "sparkle")
                    .accessibilityHidden(true)
                    .font(.system(size: sparkle.size, weight: .bold))
                    .foregroundStyle(sparkle.color)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
                    .position(x: proxy.size.width * sparkle.x, y: proxy.size.height * sparkle.y)
                    .animation(reduceMotion ? nil : pop, value: isPlayed)
            }
        }
    }

    private struct Sparkle {
        let size: CGFloat
        let color: Color
        let x: CGFloat
        let y: CGFloat
    }

    private static let sparkles = [
        Sparkle(size: 13, color: .paeoniaInkLavender, x: 0.09, y: 0.28),
        Sparkle(size: 9, color: .paeoniaTextSecondary, x: 0.2, y: 0.8),
        Sparkle(size: 11, color: .paeoniaInkGold, x: 0.91, y: 0.22),
        Sparkle(size: 8, color: .paeoniaInkBlue, x: 0.85, y: 0.74),
    ]
}

/// Which hand-drawn mark a piece is. The first player draws hearts, the second loops.
private enum UltimateTicTacToeMark {
    case heart
    case loop
}

private struct UltimateTicTacToePiece: Identifiable {
    /// The cell of its small board, 0 to 8 row by row.
    let cell: Int
    let mark: UltimateTicTacToeMark

    var id: Int { cell }
}

/// The grid and the camera. `progress` runs from 0 to 1 at an even pace. The camera zooms
/// in on one small board, waits while its marks are inked, zooms out, and then the win
/// shows: a strike line, the faded marks, and a glow on the board the next move goes to.
private struct UltimateTicTacToeScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    static let boardSize: CGFloat = 40
    static let gap: CGFloat = 6
    static let gridSize = boardSize * 3 + gap * 2
    static let zoom: CGFloat = 3.1
    /// The board the camera zooms into, in the middle on the left.
    static let focusBoard = 3
    /// The board the last move sends the next player to, in the bottom right corner.
    static let sentBoard = 8

    private static let zoomInStart = 0.1
    private static let zoomInEnd = 0.24
    private static let zoomOutStart = 0.7
    private static let zoomOutEnd = 0.84
    private static let firstMark = 0.26
    private static let markStep = 0.086
    private static let markSpan = 0.07
    private static let strikeStart = 0.84
    private static let strikeEnd = 0.91
    private static let settleStart = 0.87
    private static let settleEnd = 0.94
    private static let glowStart = 0.88
    private static let glowEnd = 0.95

    /// The moves inked in the focus board. Hearts line up on the diagonal, and the loops
    /// do not block it.
    static let plays = [
        UltimateTicTacToePiece(cell: 4, mark: .heart),
        UltimateTicTacToePiece(cell: 2, mark: .loop),
        UltimateTicTacToePiece(cell: 0, mark: .heart),
        UltimateTicTacToePiece(cell: 6, mark: .loop),
        UltimateTicTacToePiece(cell: 8, mark: .heart),
    ]

    /// Marks already on the other boards, so the game looks well underway.
    static let otherBoards: [Int: [UltimateTicTacToePiece]] = [
        0: [UltimateTicTacToePiece(cell: 0, mark: .heart), UltimateTicTacToePiece(cell: 4, mark: .loop)],
        1: [UltimateTicTacToePiece(cell: 1, mark: .loop), UltimateTicTacToePiece(cell: 5, mark: .heart)],
        2: [UltimateTicTacToePiece(cell: 4, mark: .heart)],
        4: [UltimateTicTacToePiece(cell: 2, mark: .loop), UltimateTicTacToePiece(cell: 7, mark: .heart)],
        5: [UltimateTicTacToePiece(cell: 6, mark: .heart), UltimateTicTacToePiece(cell: 3, mark: .loop)],
        6: [UltimateTicTacToePiece(cell: 7, mark: .heart)],
        7: [UltimateTicTacToePiece(cell: 8, mark: .loop), UltimateTicTacToePiece(cell: 0, mark: .heart)],
    ]

    /// Where a small board's middle is, from the middle of the grid.
    static func offset(ofBoard board: Int) -> CGSize {
        CGSize(
            width: CGFloat(board % 3 - 1) * (boardSize + gap),
            height: CGFloat(board / 3 - 1) * (boardSize + gap)
        )
    }

    /// 0 before `start`, 1 after `end`, and a smooth ease in between.
    static func ease(_ value: Double, from start: Double, to end: Double) -> Double {
        let fraction = min(max((value - start) / (end - start), 0), 1)
        return fraction * fraction * (3 - 2 * fraction)
    }

    /// A single swell from 0 up to 1 and back to 0 over `length`, starting at `start`.
    static func bump(_ value: Double, from start: Double, length: Double) -> Double {
        sin(Double.pi * min(max((value - start) / length, 0), 1))
    }

    var body: some View {
        let zoomed = Self.ease(progress, from: Self.zoomInStart, to: Self.zoomInEnd)
            - Self.ease(progress, from: Self.zoomOutStart, to: Self.zoomOutEnd)
        let scale = 1 + (Self.zoom - 1) * CGFloat(zoomed)
        // Moving the focus board to the middle of the view takes its offset, scaled up.
        let focus = Self.offset(ofBoard: Self.focusBoard)
        grid(zoomed: zoomed)
            .scaleEffect(scale)
            .offset(x: -focus.width * scale * CGFloat(zoomed), y: -focus.height * scale * CGFloat(zoomed))
    }

    private func grid(zoomed: Double) -> some View {
        ZStack {
            VStack(spacing: Self.gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<3, id: \.self) { column in
                            let board = row * 3 + column
                            UltimateTicTacToeSmallBoard(pieces: Self.otherBoards[board] ?? [])
                                // The other boards fall back while the camera is in close.
                                .opacity(board == Self.focusBoard ? 1 : 1 - 0.6 * zoomed)
                        }
                    }
                }
            }
            focusBoardOverlay(zoomed: zoomed)
            sentBoardGlow
        }
        .frame(width: Self.gridSize, height: Self.gridSize)
    }

    /// What is drawn on the focus board: its ring while it is the active board, the marks
    /// as they are inked, then the strike line, a tint, and the marks fading back.
    private func focusBoardOverlay(zoomed: Double) -> some View {
        let strike = Self.ease(progress, from: Self.strikeStart, to: Self.strikeEnd)
        let settle = Self.ease(progress, from: Self.settleStart, to: Self.settleEnd)
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
        return ZStack {
            shape.fill(Color.boardGameMine.opacity(0.2 * settle))
            shape.strokeBorder(Color.boardGameMine.opacity(0.6 * zoomed), lineWidth: 1)
            ForEach(Self.plays.indices, id: \.self) { index in
                let play = Self.plays[index]
                let start = Self.firstMark + Self.markStep * Double(index)
                UltimateTicTacToeMarkView(
                    mark: play.mark,
                    drawn: Self.ease(progress, from: start, to: start + Self.markSpan)
                )
                .frame(width: UltimateTicTacToeSmallBoard.markSize, height: UltimateTicTacToeSmallBoard.markSize)
                .offset(UltimateTicTacToeSmallBoard.offset(ofCell: play.cell))
                .opacity(1 - 0.6 * settle)
            }
            UltimateTicTacToeStrike()
                .trim(from: 0, to: strike)
                .stroke(Color.paeoniaInkGold, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .shadow(color: Color.paeoniaInkGold.opacity(0.8 * strike), radius: 2.5)
        }
        .frame(width: Self.boardSize, height: Self.boardSize)
        .offset(Self.offset(ofBoard: Self.focusBoard))
    }

    /// The board the next player must play in, glowing in their color with one soft pulse.
    private var sentBoardGlow: some View {
        let lit = Self.ease(progress, from: Self.glowStart, to: Self.glowEnd)
        let glow = lit * (1 + 0.4 * Self.bump(progress, from: Self.glowStart, length: 0.1))
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
        return shape
            .fill(Color.boardGamePartner.opacity(0.14 * glow))
            .overlay { shape.strokeBorder(Color.boardGamePartner.opacity(0.9 * glow), lineWidth: 1.2) }
            .shadow(color: Color.boardGamePartner.opacity(0.7 * glow), radius: 6)
            .frame(width: Self.boardSize, height: Self.boardSize)
            .offset(Self.offset(ofBoard: Self.sentBoard))
    }
}

/// One small board with the marks already on it.
private struct UltimateTicTacToeSmallBoard: View {
    let pieces: [UltimateTicTacToePiece]

    static let inset: CGFloat = 5
    static let cellSize = (UltimateTicTacToeScene.boardSize - inset * 2) / 3
    static let markSize = cellSize * 0.62

    /// Where a cell's middle is, from the middle of the board.
    static func offset(ofCell cell: Int) -> CGSize {
        CGSize(width: CGFloat(cell % 3 - 1) * cellSize, height: CGFloat(cell / 3 - 1) * cellSize)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
                .fill(Color.paeoniaBackgroundSecondary.opacity(0.7))
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
                .strokeBorder(Color.paeoniaInkLavender.opacity(0.4), lineWidth: PaeoniaRadius.strokeHairline)
            UltimateTicTacToeHash()
                .stroke(Color.paeoniaTextTertiary, style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                .padding(Self.inset)
            ForEach(pieces) { piece in
                UltimateTicTacToeMarkView(mark: piece.mark, drawn: 1)
                    .frame(width: Self.markSize, height: Self.markSize)
                    .offset(Self.offset(ofCell: piece.cell))
            }
        }
        .frame(width: UltimateTicTacToeScene.boardSize, height: UltimateTicTacToeScene.boardSize)
    }
}

/// A mark in its owner's color, inked from its first point as far as `drawn` (0 to 1).
/// The line width is for the whole grid, so the camera zoom thickens it with everything else.
private struct UltimateTicTacToeMarkView: View {
    let mark: UltimateTicTacToeMark
    let drawn: Double

    private static let style = StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)

    var body: some View {
        switch mark {
        case .heart:
            UltimateTicTacToeHeart()
                .trim(from: 0, to: drawn)
                .stroke(Color.boardGameMine, style: Self.style)
        case .loop:
            UltimateTicTacToeLoop()
                .trim(from: 0, to: drawn)
                .stroke(Color.boardGamePartner, style: Self.style)
        }
    }
}

/// The two lines each way that make a tic-tac-toe board.
private struct UltimateTicTacToeHash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...2 {
            let x = rect.minX + rect.width * CGFloat(step) / 3
            let y = rect.minY + rect.height * CGFloat(step) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// A hand-drawn heart, one stroke from the bottom point around and back.
private struct UltimateTicTacToeHeart: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.5, 0.92))
        path.addCurve(to: point(0.08, 0.36), control1: point(0.3, 0.76), control2: point(0.05, 0.58))
        path.addCurve(to: point(0.5, 0.28), control1: point(0.1, 0.1), control2: point(0.42, 0.1))
        path.addCurve(to: point(0.92, 0.36), control1: point(0.58, 0.1), control2: point(0.9, 0.12))
        path.addCurve(to: point(0.5, 0.92), control1: point(0.95, 0.58), control2: point(0.7, 0.76))
        return path
    }
}

/// A hand-drawn loop. It starts at the top and runs a little more than once around,
/// tightening, so the end crosses the start the way a quick "o" does.
private struct UltimateTicTacToeLoop: Shape {
    func path(in rect: CGRect) -> Path {
        let steps = 40
        var path = Path()
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let angle = -Double.pi / 2 + fraction * 2 * Double.pi * 1.1
            let reach = 0.5 - 0.06 * fraction
            let point = CGPoint(
                x: rect.midX + CGFloat(cos(angle) * reach) * rect.width,
                y: rect.midY + CGFloat(sin(angle) * reach) * rect.height
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A slightly bowed line from the top left cell to the bottom right cell of a small board.
private struct UltimateTicTacToeStrike: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.2))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.8),
            control: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.47)
        )
        return path
    }
}

#if DEBUG
#Preview {
    UltimateTicTacToeHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
