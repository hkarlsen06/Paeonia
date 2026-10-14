import SwiftUI

/// The picture at the top of the Dots and Boxes card: a board of dots where lines snap
/// in from their middle, and every box that closes opens onto a piece of a sunset photo,
/// tinted in the color of the partner who closed it. The photo is the twist of the game, so
/// it only shows in the boxes that are closed. It plays once when the card appears. With
/// Reduce Motion it starts finished.
struct DotsAndBoxesHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 5.5
    private static let playDelay: TimeInterval = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            sparkles(shown: shown)
            DotsAndBoxesScene(progress: shown ? 1 : 0)
                // An even pace, so each line can snap in on its own (see `DotsAndBoxesScene`).
                .animation(
                    reduceMotion ? nil : .linear(duration: Self.playDuration).delay(Self.playDelay),
                    value: isPlayed
                )
                .rotationEffect(.degrees(-3))
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

    /// A low sun behind the board, so the whole card has the mood of the photo.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.paeoniaPartnerTwo.opacity(0.45), .clear],
                center: UnitPoint(x: 0.5, y: 1.05),
                startRadius: 0,
                endRadius: 260
            )
            RadialGradient(
                colors: [Color.paeoniaInkGold.opacity(0.3), .clear],
                center: UnitPoint(x: 0.5, y: 1.05),
                startRadius: 0,
                endRadius: 150
            )
            RadialGradient(
                colors: [.paeoniaAccentSecondary.opacity(0.35), .clear],
                center: UnitPoint(x: 0.1, y: 0.05),
                startRadius: 0,
                endRadius: 200
            )
        }
    }

    private func sparkles(shown: Bool) -> some View {
        GeometryReader { proxy in
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                let pop = PaeoniaMotion.cardReveal.delay(
                    Self.playDelay + Self.playDuration * (0.9 + 0.03 * Double(index))
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
        Sparkle(size: 13, color: .paeoniaInkGold, x: 0.1, y: 0.62),
        Sparkle(size: 9, color: .paeoniaMemory, x: 0.18, y: 0.2),
        Sparkle(size: 11, color: .paeoniaAccentPrimary, x: 0.9, y: 0.3),
        Sparkle(size: 8, color: .paeoniaInkGold, x: 0.84, y: 0.78),
    ]
}

/// The board. `progress` runs from 0 to 1 at an even pace. Each line takes its own slice
/// of it and springs out from its middle to the two dots it joins, and the dots pulse.
/// A box opens onto its piece of the photo just after its fourth line lands.
private struct DotsAndBoxesScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    static let dotsPerSide = 5
    static let spacing: CGFloat = 26
    static let side = spacing * 4
    static let inset: CGFloat = 16
    static let plateSize = side + inset * 2
    static let lineWidth: CGFloat = 2.8
    static let dotSize: CGFloat = 5.5

    private static let firstLine = 0.03
    private static let lineStep = 0.032
    private static let lineSpan = 0.075
    private static let boxDelay = 0.045
    private static let boxSpan = 0.09

    /// A line between two neighboring dots. Rows and columns count from the top left.
    /// A horizontal line sits on a row of dots, a vertical line sits on a column of dots.
    struct Line: Hashable {
        let isHorizontal: Bool
        let row: Int
        let column: Int

        static func horizontal(_ row: Int, _ column: Int) -> Line {
            Line(isHorizontal: true, row: row, column: column)
        }

        static func vertical(_ row: Int, _ column: Int) -> Line {
            Line(isHorizontal: false, row: row, column: column)
        }

        /// The middle of the line, from the top left dot.
        var middle: CGPoint {
            let spacing = DotsAndBoxesScene.spacing
            if isHorizontal {
                return CGPoint(x: (CGFloat(column) + 0.5) * spacing, y: CGFloat(row) * spacing)
            }
            return CGPoint(x: CGFloat(column) * spacing, y: (CGFloat(row) + 0.5) * spacing)
        }

        /// The two dots it joins, numbered row by row.
        var endDots: [Int] {
            let first = row * DotsAndBoxesScene.dotsPerSide + column
            return [first, first + (isHorizontal ? 1 : DotsAndBoxesScene.dotsPerSide)]
        }
    }

    struct Box {
        let row: Int
        let column: Int
        let isMine: Bool

        var lines: [Line] {
            [.horizontal(row, column), .horizontal(row + 1, column), .vertical(row, column), .vertical(row, column + 1)]
        }

        var tint: Color { isMine ? .boardGameMine : .boardGamePartner }
    }

    /// The lines in the order they are drawn. Seven boxes close, and a few lines stand on
    /// their own. Two boxes are left one line short, so the game still feels open.
    static let moves: [Line] = [
        .horizontal(1, 1), .vertical(1, 1), .horizontal(2, 1), .vertical(1, 2),
        .horizontal(0, 1), .horizontal(1, 2), .vertical(0, 1), .horizontal(2, 2), .vertical(1, 3),
        .vertical(2, 1), .horizontal(3, 1), .vertical(2, 2),
        .horizontal(3, 2), .vertical(2, 3),
        .vertical(3, 0), .horizontal(4, 1), .vertical(3, 1), .vertical(3, 2),
        .horizontal(4, 2), .vertical(3, 3),
        .horizontal(2, 3), .horizontal(0, 3), .vertical(0, 3), .horizontal(1, 3), .vertical(0, 4),
    ]

    /// The boxes the lines close. The four in the middle hold the sun of the photo.
    static let boxes = [
        Box(row: 1, column: 1, isMine: true),
        Box(row: 1, column: 2, isMine: false),
        Box(row: 2, column: 1, isMine: false),
        Box(row: 2, column: 2, isMine: true),
        Box(row: 3, column: 1, isMine: true),
        Box(row: 3, column: 2, isMine: false),
        Box(row: 0, column: 3, isMine: true),
    ]

    private static let moveIndex = Dictionary(
        uniqueKeysWithValues: moves.enumerated().map { ($0.element, $0.offset) }
    )

    /// For every dot, when each line that touches it starts to snap in.
    private static let dotTouches: [[Double]] = {
        let dotCount = DotsAndBoxesScene.dotsPerSide * DotsAndBoxesScene.dotsPerSide
        var touches = [[Double]](repeating: [], count: dotCount)
        for (index, line) in DotsAndBoxesScene.moves.enumerated() {
            for dot in line.endDots {
                touches[dot].append(DotsAndBoxesScene.start(ofMove: index))
            }
        }
        return touches
    }()

    static func start(ofMove index: Int) -> Double {
        firstLine + lineStep * Double(index)
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

    /// How much of a line is drawn, `time` (0 to 1) into its slice. It grows past 1 a little
    /// and settles back, like a spring.
    static func snap(_ time: Double) -> Double {
        guard time > 0 else { return 0 }
        guard time < 1 else { return 1 }
        return 1 - exp(-6.5 * time) * cos(10 * time)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                .fill(Color.paeoniaBackgroundSecondary.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                        .strokeBorder(Color.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                }
                .shadow(color: Color.paeoniaBackgroundSecondary.opacity(0.6), radius: 18, y: 10)
            board
        }
        .frame(width: Self.plateSize, height: Self.plateSize)
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            // Lines nobody has drawn yet, as a faint dotted guide.
            DotsAndBoxesGuides(spacing: Self.spacing)
                .stroke(
                    Color.paeoniaTextPrimary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 4])
                )
            DotsAndBoxesPhoto(side: Self.side)
                .mask { pieces(tinted: false) }
                .overlay { pieces(tinted: true) }
            lines
            dots
        }
        .frame(width: Self.side, height: Self.side)
    }

    /// One square for every box, growing in as the box closes. As a mask it uncovers the
    /// photo, and tinted it colors the piece for whoever closed the box.
    private func pieces(tinted: Bool) -> some View {
        ZStack {
            ForEach(Self.boxes.indices, id: \.self) { index in
                let box = Self.boxes[index]
                let opened = opening(of: box)
                Rectangle()
                    .fill(tinted ? box.tint.opacity(0.32) : Color.paeoniaTextPrimary)
                    .frame(width: Self.spacing, height: Self.spacing)
                    .scaleEffect(0.85 + 0.15 * opened)
                    .opacity(opened)
                    .position(
                        x: (CGFloat(box.column) + 0.5) * Self.spacing,
                        y: (CGFloat(box.row) + 0.5) * Self.spacing
                    )
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    /// How open a box is, from 0 to 1. It starts when its last line has begun to snap in.
    private func opening(of box: Box) -> Double {
        let last = box.lines.compactMap { Self.moveIndex[$0] }.max() ?? 0
        let start = Self.start(ofMove: last) + Self.boxDelay
        return Self.ease(progress, from: start, to: start + Self.boxSpan)
    }

    private var lines: some View {
        ZStack {
            ForEach(Self.moves.indices, id: \.self) { index in
                let line = Self.moves[index]
                let time = (progress - Self.start(ofMove: index)) / Self.lineSpan
                let length = Self.spacing * CGFloat(Self.snap(time))
                Capsule()
                    .fill(Color.paeoniaTextPrimary)
                    .frame(
                        width: line.isHorizontal ? length : Self.lineWidth,
                        height: line.isHorizontal ? Self.lineWidth : length
                    )
                    .position(line.middle)
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    private var dots: some View {
        ZStack {
            ForEach(0..<(Self.dotsPerSide * Self.dotsPerSide), id: \.self) { index in
                Circle()
                    .fill(Color.paeoniaTextPrimary)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .scaleEffect(1 + 0.6 * pulse(ofDot: index))
                    .position(
                        x: CGFloat(index % Self.dotsPerSide) * Self.spacing,
                        y: CGFloat(index / Self.dotsPerSide) * Self.spacing
                    )
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    /// A dot swells once each time a line reaches it.
    private func pulse(ofDot index: Int) -> Double {
        Self.dotTouches[index]
            .map { Self.bump(progress, from: $0 + 0.1 * Self.lineSpan, length: Self.lineSpan) }
            .max() ?? 0
    }
}

/// Every possible line of the board, as one path.
private struct DotsAndBoxesGuides: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for dotRow in 0...4 {
            for box in 0..<4 {
                let along = CGFloat(box) * spacing
                let across = CGFloat(dotRow) * spacing
                path.move(to: CGPoint(x: along, y: across))
                path.addLine(to: CGPoint(x: along + spacing, y: across))
                path.move(to: CGPoint(x: across, y: along))
                path.addLine(to: CGPoint(x: across, y: along + spacing))
            }
        }
        return path
    }
}

/// The hidden photo, drawn instead of loaded: a sunset over water. Each box of the board
/// shows its own square of it.
private struct DotsAndBoxesPhoto: View {
    let side: CGFloat

    private static let horizon = 0.68

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: .paeoniaInkLavender, location: 0),
                    .init(color: .paeoniaAccentPrimary, location: 0.3),
                    .init(color: .paeoniaPartnerTwo, location: 0.46),
                    .init(color: .paeoniaInkGold, location: 0.6),
                    .init(color: .paeoniaMemory, location: 0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            sun
            DotsAndBoxesHills(horizon: Self.horizon)
                .fill(Color.paeoniaBackgroundPrimary.opacity(0.85))
            sea
        }
        .frame(width: side, height: side)
    }

    private var sun: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.paeoniaMemory, .paeoniaInkGold],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.15
                )
            )
            .frame(width: side * 0.3, height: side * 0.3)
            .shadow(color: Color.paeoniaInkGold.opacity(0.8), radius: side * 0.08)
            .position(x: side * 0.5, y: side * 0.57)
    }

    /// Water below the horizon, with the sun's glitter on it.
    private var sea: some View {
        let top = side * Self.horizon
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.paeoniaPartnerTwo, .paeoniaSurfacePressed],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: side, height: side - top)
                .offset(y: top)
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill((index.isMultiple(of: 2) ? Color.paeoniaInkGold : Color.paeoniaMemory).opacity(0.85))
                    .frame(width: side * (0.22 - 0.045 * CGFloat(index)), height: side * 0.02)
                    .position(x: side * 0.5, y: side * (0.72 + 0.075 * CGFloat(index)))
            }
        }
    }
}

/// Two low hills on the horizon.
private struct DotsAndBoxesHills: Shape {
    /// Where the water starts, as a fraction of the height.
    let horizon: Double

    func path(in rect: CGRect) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0, horizon + 0.02))
        path.addLine(to: point(0, horizon))
        path.addQuadCurve(to: point(0.34, horizon), control: point(0.17, horizon - 0.18))
        path.addLine(to: point(0.62, horizon))
        path.addQuadCurve(to: point(1, horizon), control: point(0.82, horizon - 0.14))
        path.addLine(to: point(1, horizon + 0.02))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview {
    DotsAndBoxesHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
