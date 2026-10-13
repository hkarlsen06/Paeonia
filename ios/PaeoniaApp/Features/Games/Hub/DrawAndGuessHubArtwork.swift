import SwiftUI

/// The picture at the top of the Draw & Guess card: a pencil drawing a heart on a
/// sheet of paper, and the letter tiles that spell what it is. It plays once when
/// the card appears. With Reduce Motion it starts finished.
struct DrawAndGuessHubArtwork: View {
    static let height: CGFloat = 200
    private static let drawDuration: TimeInterval = 5
    private static let drawDelay: TimeInterval = 0.3
    private static let tileSize: CGFloat = 34
    private static let tileSpacing: CGFloat = 6
    private static let tilesPerRow = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    var body: some View {
        ZStack {
            background
            sparkles
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                sketch
                Spacer(minLength: 0)
                tiles
                Spacer(minLength: 0)
            }
            .padding(.top, PaeoniaSpacing.space24)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        .onAppear {
            guard !isDrawn else { return }
            if reduceMotion {
                isDrawn = true
            } else {
                withAnimation(PaeoniaMotion.meaningfulMoment.delay(Self.drawDelay)) { isDrawn = true }
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.45), .clear],
                center: UnitPoint(x: 0.85, y: 0.1),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.3), .clear],
                center: UnitPoint(x: 0.05, y: 0.95),
                startRadius: 0,
                endRadius: 200
            )
        }
    }

    private var sparkles: some View {
        GeometryReader { proxy in
            ForEach(Self.sparkles.indices, id: \.self) { index in
                let sparkle = Self.sparkles[index]
                Image(systemName: "sparkle")
                    .accessibilityHidden(true)
                    .font(.system(size: sparkle.size, weight: .bold))
                    .foregroundStyle(sparkle.color)
                    .position(x: proxy.size.width * sparkle.x, y: proxy.size.height * sparkle.y)
                    .opacity(isDrawn ? 1 : 0)
                    .scaleEffect(isDrawn ? 1 : 0.3)
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
        Sparkle(size: 14, color: .paeoniaInkGold, x: 0.06, y: 0.6),
        Sparkle(size: 9, color: .paeoniaTextSecondary, x: 0.6, y: 0.16),
        Sparkle(size: 11, color: .paeoniaTextPrimary, x: 0.92, y: 0.62),
        Sparkle(size: 8, color: .paeoniaInkGold, x: 0.56, y: 0.9),
    ]

    /// The paper, with the pencil drawing on it.
    private var sketch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .fill(.paeoniaWidgetDrawing)
                .shadow(color: .paeoniaBackgroundSecondary.opacity(0.6), radius: 18, y: 10)

            DoodleDrawing(progress: isDrawn ? 1 : 0)
                // An even pace, so each stroke can ease on its own (see `DoodleDrawing`).
                .animation(
                    reduceMotion ? nil : .linear(duration: Self.drawDuration).delay(Self.drawDelay),
                    value: isDrawn
                )
        }
        .frame(width: 144, height: 136)
        .rotationEffect(.degrees(-6))
    }

    /// The letters of what the doodle shows. They pop in one by one once the heart is drawn.
    private var tiles: some View {
        let letters = Array(String(localized: .gamesHubArtworkWord))
        let rows = stride(from: 0, to: letters.count, by: Self.tilesPerRow).map { start in
            Array(start..<min(start + Self.tilesPerRow, letters.count))
        }
        return VStack(spacing: Self.tileSpacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: Self.tileSpacing) {
                    ForEach(row, id: \.self) { index in
                        tile(letters[index], index: index)
                    }
                }
            }
        }
        .frame(width: CGFloat(Self.tilesPerRow) * (Self.tileSize + Self.tileSpacing), height: 136)
    }

    private static let tileColors: [Color] = [
        .paeoniaAccentPrimary, .paeoniaInkGold, .paeoniaInkLavender, .paeoniaInkBlue, .paeoniaAccentSecondary,
    ]
    private static let tileTilts: [Double] = [-8, 5, -3, 7, -6, 4]

    private func tile(_ letter: Character, index: Int) -> some View {
        let pop = PaeoniaMotion.cardReveal.delay(Self.drawDelay + Self.drawDuration * 0.5 + Double(index) * 0.12)
        return Text(String(letter))
            .font(.system(size: Self.tileSize * 0.52, weight: .bold, design: .rounded))
            .foregroundStyle(.paeoniaTextInverse)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .background(
                Self.tileColors[index % Self.tileColors.count],
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
            )
            .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 6, y: 3)
            .rotationEffect(.degrees(Self.tileTilts[index % Self.tileTilts.count]))
            .offset(y: index.isMultiple(of: 2) ? -2 : 2)
            .scaleEffect(isDrawn ? 1 : 0.3)
            .opacity(isDrawn ? 1 : 0)
            .animation(reduceMotion ? nil : pop, value: isDrawn)
    }
}

/// The doodle and the pencil drawing it. `progress` runs from 0 to 1 at an even
/// pace. Each stroke takes its own share of it and eases in and out, and the pencil
/// tip stays on the end of the line. The pencil leans against the way the tip moves,
/// as a hand drags it. Between strokes it lifts, stands up a little, and moves to
/// where the next one starts.
private struct DoodleDrawing: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let size = CGSize(width: 120, height: 112)
    /// The pencil's tilt from upright, in degrees, before the stroke direction moves it.
    private static let restingTilt = 34.0

    private struct Stroke {
        let path: Path
        let color: Color
        let width: CGFloat
        let start: Double
        let end: Double
        /// How much of the path the tilt looks along, so sharp corners turn the pencil smoothly.
        let tiltWindow: Double

        /// How much of the stroke is drawn, eased so the pencil slows at each end.
        func drawn(at progress: Double) -> Double {
            let linear = min(max((progress - start) / (end - start), 0), 1)
            return linear * linear * (3 - 2 * linear)
        }
    }

    var body: some View {
        let strokes = Self.strokes
        let pencil = pencilPlacement(strokes)
        ZStack {
            ForEach(strokes.indices, id: \.self) { index in
                let stroke = strokes[index]
                stroke.path
                    .trimmedPath(from: 0, to: stroke.drawn(at: progress))
                    .stroke(
                        stroke.color,
                        style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
                    )
            }
            DoodlePencil()
                .scaleEffect(1 + 0.08 * pencil.lift, anchor: .bottom)
                .rotationEffect(.degrees(pencil.tilt), anchor: .bottom)
                .position(x: pencil.tip.x, y: pencil.tip.y - DoodlePencil.length / 2 - 10 * pencil.lift)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private static var strokes: [Stroke] {
        let rect = CGRect(origin: .zero, size: size)
        return [
            Stroke(
                path: DoodleHeart().path(in: rect), color: .paeoniaAccentSecondary, width: 6,
                start: 0, end: 0.5, tiltWindow: 0.08
            ),
            Stroke(
                path: DoodleStar().path(in: rect), color: .paeoniaInkGold, width: 4,
                start: 0.58, end: 0.76, tiltWindow: 0.2
            ),
            Stroke(
                path: DoodleSquiggle().path(in: rect), color: .paeoniaInkBlue, width: 4,
                start: 0.84, end: 1, tiltWindow: 0.12
            ),
        ]
    }

    private struct PencilPlacement {
        let tip: CGPoint
        /// How far the pencil is off the paper, from 0 to 1.
        let lift: Double
        let tilt: Double
    }

    private func pencilPlacement(_ strokes: [Stroke]) -> PencilPlacement {
        // A slow, small wobble, like a hand that is never quite still.
        let wobble = 2 * sin(progress * 23)
        for (index, stroke) in strokes.enumerated() where progress <= stroke.end {
            if progress >= stroke.start || index == 0 {
                let drawn = stroke.drawn(at: progress)
                return PencilPlacement(
                    tip: Self.point(on: stroke.path, at: drawn),
                    lift: 0,
                    tilt: Self.tilt(on: stroke, at: drawn) + wobble
                )
            }
            let previous = strokes[index - 1]
            let travel = (progress - previous.end) / (stroke.start - previous.end)
            let eased = travel * travel * (3 - 2 * travel)
            let from = Self.point(on: previous.path, at: 1)
            let to = Self.point(on: stroke.path, at: 0)
            let fromTilt = Self.tilt(on: previous, at: 1)
            let toTilt = Self.tilt(on: stroke, at: 0)
            let lift = sin(travel * .pi)
            return PencilPlacement(
                tip: CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased),
                lift: lift,
                tilt: fromTilt + (toTilt - fromTilt) * eased - 12 * lift + wobble
            )
        }
        let last = strokes[strokes.count - 1]
        return PencilPlacement(
            tip: Self.point(on: last.path, at: 1),
            lift: 0,
            tilt: Self.tilt(on: last, at: 1) + wobble
        )
    }

    /// The top of the pencil trails behind the tip. Moving right leans it left, and
    /// moving left leans it right.
    private static func tilt(on stroke: Stroke, at fraction: Double) -> Double {
        let before = point(on: stroke.path, at: max(fraction - stroke.tiltWindow, 0))
        let after = point(on: stroke.path, at: min(fraction + stroke.tiltWindow, 1))
        let dx = after.x - before.x
        let length = max(hypot(dx, after.y - before.y), 0.001)
        return restingTilt - 16 * dx / length
    }

    private static func point(on path: Path, at fraction: Double) -> CGPoint {
        // An empty trim has no current point, so start just past zero.
        path.trimmedPath(from: 0, to: max(fraction, 0.001)).currentPoint ?? .zero
    }
}

/// A yellow pencil, tip down.
private struct DoodlePencil: View {
    private static let eraserHeight: CGFloat = 12
    private static let bandHeight: CGFloat = 7
    private static let bodyHeight: CGFloat = 44
    private static let tipHeight: CGFloat = 18
    static let length = eraserHeight + bandHeight + bodyHeight + tipHeight

    var body: some View {
        VStack(spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                .fill(.paeoniaAccentPrimary)
                .frame(height: Self.eraserHeight)
            Rectangle()
                .fill(.paeoniaTextSecondary)
                .frame(height: Self.bandHeight)
            Rectangle()
                .fill(Color.paeoniaInkGold)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.paeoniaBackgroundSecondary.opacity(0.15)).frame(width: 5)
                }
                .frame(height: Self.bodyHeight)
            DoodleTriangle()
                .fill(.paeoniaMemory)
                .overlay(alignment: .bottom) {
                    DoodleTriangle()
                        .fill(.paeoniaBackgroundSecondary)
                        .frame(width: 6, height: 6)
                }
                .frame(height: Self.tipHeight)
        }
        .frame(width: 16)
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 6, x: 3, y: 5)
    }
}

private struct DoodleTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// A hand-drawn heart.
private struct DoodleHeart: Shape {
    func path(in rect: CGRect) -> Path {
        let point = rect.unitPoint
        return Path { path in
            path.move(to: point(0.42, 0.8))
            path.addCurve(to: point(0.12, 0.38), control1: point(0.28, 0.68), control2: point(0.1, 0.54))
            path.addCurve(to: point(0.42, 0.3), control1: point(0.14, 0.14), control2: point(0.38, 0.14))
            path.addCurve(to: point(0.72, 0.38), control1: point(0.46, 0.14), control2: point(0.7, 0.14))
            path.addCurve(to: point(0.42, 0.8), control1: point(0.74, 0.54), control2: point(0.56, 0.68))
        }
    }
}

private struct DoodleStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.18)
        let outer = rect.width * 0.11
        return Path { path in
            for index in 0...10 {
                let radius = index.isMultiple(of: 2) ? outer : outer * 0.45
                let angle = Double(index) * .pi / 5 - .pi / 2
                let vertex = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
            }
        }
    }
}

private struct DoodleSquiggle: Shape {
    func path(in rect: CGRect) -> Path {
        let point = rect.unitPoint
        return Path { path in
            path.move(to: point(0.14, 0.96))
            for hump in 0..<4 {
                let x = 0.14 + Double(hump) * 0.16
                let lift = hump.isMultiple(of: 2) ? 0.88 : 1.04
                path.addQuadCurve(to: point(x + 0.16, 0.96), control: point(x + 0.08, lift))
            }
        }
    }
}

private extension CGRect {
    /// Maps fractions of the rect to a point in it.
    var unitPoint: (Double, Double) -> CGPoint {
        { x, y in CGPoint(x: minX + width * x, y: minY + height * y) }
    }
}

#if DEBUG
#Preview {
    DrawAndGuessHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
