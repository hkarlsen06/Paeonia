import SwiftUI

/// The picture at the top of the Connect Four card: a tilted board where discs in both
/// partner colors drop in one after another, each with its owner's little mark, until
/// four in a row light up. It plays once when the card appears. With Reduce Motion it
/// starts finished.
struct ConnectFourHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 5
    private static let playDelay: TimeInterval = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            sparkles(shown: shown)
            ConnectFourScene(progress: shown ? 1 : 0)
                // An even pace, so each disc can fall and bounce on its own (see `ConnectFourScene`).
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

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // A rose glow behind the board, so its plum face stands out.
            RadialGradient(
                colors: [.paeoniaAccentSecondary.opacity(0.5), .clear],
                center: UnitPoint(x: 0.5, y: 0.55),
                startRadius: 0,
                endRadius: 200
            )
            RadialGradient(
                colors: [Color.paeoniaInkGold.opacity(0.2), .clear],
                center: UnitPoint(x: 0.05, y: 0.05),
                startRadius: 0,
                endRadius: 190
            )
        }
    }

    private func sparkles(shown: Bool) -> some View {
        GeometryReader { proxy in
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                let pop = PaeoniaMotion.cardReveal.delay(
                    Self.playDelay + Self.playDuration * (0.88 + 0.03 * Double(index))
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
        Sparkle(size: 13, color: .paeoniaInkGold, x: 0.09, y: 0.3),
        Sparkle(size: 9, color: .paeoniaTextSecondary, x: 0.17, y: 0.78),
        Sparkle(size: 11, color: .paeoniaTextPrimary, x: 0.91, y: 0.24),
        Sparkle(size: 8, color: .paeoniaInkGold, x: 0.86, y: 0.72),
    ]
}

/// The board and its discs. `progress` runs from 0 to 1 at an even pace. Each disc takes
/// its own slice of it and falls with gravity, bounces twice, and then its mark is drawn.
/// When the last disc has landed, the four in a row light up one after another.
///
/// The discs sit between a dark back panel and the board face, so a falling disc shows
/// through the holes.
private struct ConnectFourScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    static let columns = 7
    static let rows = 6
    static let cell: CGFloat = 19
    static let inset: CGFloat = 7
    static let holeSize: CGFloat = 15
    static let discSize: CGFloat = 17
    static let cornerRadius = PaeoniaRadius.radius16
    static let boardWidth = CGFloat(columns) * cell + inset * 2
    static let boardHeight = CGFloat(rows) * cell + inset * 2

    private static let firstDrop = 0.03
    private static let dropStep = 0.11
    private static let dropSpan = 0.16
    private static let glowStart = 0.8
    private static let glowSpan = 0.1
    private static let glowStagger = 0.02

    struct Drop {
        let column: Int
        /// 0 is the bottom row.
        let row: Int
        let isMine: Bool
        let isWinning: Bool
    }

    /// Seven moves. The first player builds a row on the bottom. The second player stacks
    /// on top and blocks one end, and the first player finishes the other end.
    static let drops = [
        Drop(column: 3, row: 0, isMine: true, isWinning: true),
        Drop(column: 3, row: 1, isMine: false, isWinning: false),
        Drop(column: 4, row: 0, isMine: true, isWinning: true),
        Drop(column: 4, row: 1, isMine: false, isWinning: false),
        Drop(column: 2, row: 0, isMine: true, isWinning: true),
        Drop(column: 1, row: 0, isMine: false, isWinning: false),
        Drop(column: 5, row: 0, isMine: true, isWinning: true),
    ]

    /// The middle of a cell, from the top left corner of the board.
    static func center(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: inset + (CGFloat(column) + 0.5) * cell,
            y: inset + (CGFloat(rows - 1 - row) + 0.5) * cell
        )
    }

    /// 0 before `start`, 1 after `end`, and a smooth ease in between.
    static func ease(_ value: Double, from start: Double, to end: Double) -> Double {
        let fraction = min(max((value - start) / (end - start), 0), 1)
        return fraction * fraction * (3 - 2 * fraction)
    }

    /// How far a disc has fallen (0 to 1) and how far a bounce lifts it, in points, when the
    /// drop is `time` (0 to 1) of the way through. Gravity speeds the fall up, then two
    /// bounces, the second smaller.
    static func motion(at time: Double) -> (fall: Double, lift: Double) {
        let landing = 0.56
        guard time >= landing else {
            let gravity = time / landing
            return (gravity * gravity, 0)
        }
        let rest = (time - landing) / (1 - landing)
        if rest < 0.55 {
            return (1, 4 * arc(rest / 0.55))
        }
        return (1, 1.2 * arc((rest - 0.55) / 0.45))
    }

    /// A hop that starts and ends at 0 and peaks at 1 in the middle.
    private static func arc(_ fraction: Double) -> Double {
        4 * fraction * (1 - fraction)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ConnectFourBack()
            discs
            ConnectFourFront()
            winGlow
        }
        .frame(width: Self.boardWidth, height: Self.boardHeight)
        .rotation3DEffect(.degrees(-16), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotationEffect(.degrees(-4))
    }

    private var discs: some View {
        ZStack {
            ForEach(Self.drops.indices, id: \.self) { index in
                disc(Self.drops[index], at: index)
            }
        }
    }

    private func disc(_ drop: Drop, at index: Int) -> some View {
        let start = Self.firstDrop + Self.dropStep * Double(index)
        let time = min(max((progress - start) / Self.dropSpan, 0), 1)
        let rest = Self.center(column: drop.column, row: drop.row)
        let above = -Self.discSize
        let motion = Self.motion(at: time)
        let height = above + (rest.y - above) * CGFloat(motion.fall) - CGFloat(motion.lift)
        return ConnectFourDisc(isMine: drop.isMine, markProgress: Self.ease(time, from: 0.55, to: 0.9))
            .frame(width: Self.discSize, height: Self.discSize)
            .position(x: rest.x, y: height)
            .opacity(time > 0 ? 1 : 0)
    }

    /// A soft light over the winning row, and a lit rim around each of its holes.
    private var winGlow: some View {
        let wins = Self.drops.filter(\.isWinning)
        let columns = wins.map(\.column)
        let row = wins.first?.row ?? 0
        let left = Self.center(column: columns.min() ?? 0, row: row)
        let right = Self.center(column: columns.max() ?? 0, row: row)
        let glow = Self.ease(progress, from: Self.glowStart, to: Self.glowStart + Self.glowSpan)
        return ZStack {
            Capsule()
                .fill(Color.paeoniaTextPrimary.opacity(0.3 * glow))
                .frame(width: right.x - left.x + Self.cell, height: Self.holeSize + 5)
                .blur(radius: 6)
                .position(x: (left.x + right.x) / 2, y: left.y)
            ForEach(wins.indices, id: \.self) { index in
                rim(for: wins[index], rank: wins[index].column - (columns.min() ?? 0))
            }
        }
    }

    private func rim(for drop: Drop, rank: Int) -> some View {
        let start = Self.glowStart + Self.glowStagger * Double(rank)
        let lit = Self.ease(progress, from: start, to: start + Self.glowSpan)
        return Circle()
            .strokeBorder(Color.paeoniaTextPrimary.opacity(0.95 * lit), lineWidth: 1.5)
            .frame(width: Self.cell, height: Self.cell)
            .shadow(color: Color.paeoniaAccentPrimary.opacity(lit), radius: 4.5)
            .position(Self.center(column: drop.column, row: drop.row))
    }
}

/// The dark panel behind the discs. Empty holes show it.
private struct ConnectFourBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ConnectFourScene.cornerRadius, style: .continuous)
            .fill(Color.paeoniaBackgroundSecondary)
            .shadow(color: Color.paeoniaBackgroundSecondary.opacity(0.7), radius: 14, y: 8)
    }
}

/// The plum face of the board, with a hole for every cell.
private struct ConnectFourFront: View {
    var body: some View {
        ZStack {
            ConnectFourFaceShape()
                .fill(
                    LinearGradient(
                        colors: [.paeoniaSurfacePressed, .paeoniaSurfacePrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: FillStyle(eoFill: true)
                )
            // A light lower lip and a dark upper lip make each hole look cut into the face.
            ConnectFourFaceShape(holesOnly: true)
                .offset(y: 1)
                .stroke(Color.paeoniaAccentPrimary.opacity(0.28), lineWidth: 1)
            ConnectFourFaceShape(holesOnly: true)
                .stroke(Color.paeoniaBackgroundSecondary.opacity(0.75), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: ConnectFourScene.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.paeoniaAccentPrimary.opacity(0.6), .paeoniaAccentPrimary.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.25
                )
        }
    }
}

/// The board face as one path. Filled with the even-odd rule, the holes are see-through.
private struct ConnectFourFaceShape: Shape {
    var holesOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if !holesOnly {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: ConnectFourScene.cornerRadius, height: ConnectFourScene.cornerRadius),
                style: .continuous
            )
        }
        let hole = ConnectFourScene.holeSize
        for column in 0..<ConnectFourScene.columns {
            for row in 0..<ConnectFourScene.rows {
                let center = ConnectFourScene.center(column: column, row: row)
                path.addEllipse(in: CGRect(x: center.x - hole / 2, y: center.y - hole / 2, width: hole, height: hole))
            }
        }
        return path
    }
}

/// One disc in its owner's color, with the ridge a real disc has and the owner's mark.
private struct ConnectFourDisc: View {
    let isMine: Bool
    /// How much of the mark is drawn, from 0 to 1.
    let markProgress: Double

    private static let markStyle = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            Circle().fill(isMine ? Color.boardGameMine : Color.boardGamePartner)
            Circle()
                .strokeBorder(Color.paeoniaBackgroundSecondary.opacity(0.2), lineWidth: 1)
                .padding(3)
            mark
                .frame(width: 7.5, height: 7.5)
                .rotationEffect(.degrees(isMine ? -8 : 10))
                .shadow(color: Color.paeoniaBackgroundSecondary.opacity(0.25), radius: 0.5, y: 0.5)
        }
    }

    /// A heart for the first player, a star for the second.
    @ViewBuilder private var mark: some View {
        if isMine {
            ConnectFourHeart()
                .trim(from: 0, to: markProgress)
                .stroke(Color.paeoniaTextPrimary, style: Self.markStyle)
        } else {
            ConnectFourStar()
                .trim(from: 0, to: markProgress)
                .stroke(Color.paeoniaTextPrimary, style: Self.markStyle)
        }
    }
}

/// A hand-drawn heart, one stroke from the bottom point around and back.
private struct ConnectFourHeart: Shape {
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

/// A hand-drawn star. The points are a little uneven, like one drawn without a ruler.
private struct ConnectFourStar: Shape {
    private static let unevenness = [1.0, 0.9, 1.06, 0.94, 1.02, 0.92, 1.05, 0.96, 1.0, 0.9]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0...10 {
            let vertex = index % 10
            let reach = (vertex.isMultiple(of: 2) ? 0.5 : 0.22) * Self.unevenness[vertex]
            let angle = Double(vertex) * .pi / 5 - .pi / 2
            let point = CGPoint(
                x: rect.midX + CGFloat(cos(angle) * reach) * rect.width,
                y: rect.midY + rect.height * 0.04 + CGFloat(sin(angle) * reach) * rect.height
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

#if DEBUG
#Preview {
    ConnectFourHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
