import SwiftUI

/// The picture at the top of the Exquisite corpse card: a strip of paper in three
/// parts with two crayons beside it, one for each partner. The parts swing open from
/// the top one by one, and the crayon whose turn it is wiggles as its part opens.
/// Together they show a kitten's head, a cozy sweater and duck feet. When the feet
/// are out, the creature hops, waves and blinks, and hearts pop up. It plays once
/// when the card appears. With Reduce Motion it starts finished.
struct ExquisiteCorpseHubArtwork: View {
    static let height: CGFloat = 200
    private static let playDuration: TimeInterval = 4.2
    private static let playDelay: TimeInterval = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayed = false

    var body: some View {
        let shown = isPlayed || reduceMotion
        ZStack {
            background
            ExquisiteCorpseHubScene(progress: shown ? 1 : 0)
                // An even pace, so each part can open on its own (see `ExquisiteCorpseHubScene`).
                .animation(
                    reduceMotion ? nil : .linear(duration: Self.playDuration).delay(Self.playDelay),
                    value: isPlayed
                )
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { isPlayed = true }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.32), .clear],
                center: UnitPoint(x: 0.1, y: 0.2),
                startRadius: 0,
                endRadius: 200
            )
            RadialGradient(
                colors: [Color.paeoniaInkBlue.opacity(0.26), .clear],
                center: UnitPoint(x: 0.92, y: 0.9),
                startRadius: 0,
                endRadius: 190
            )
        }
    }
}

/// The strip, the crayons and what pops up at the end. `progress` runs from 0 to 1
/// at an even pace, and each part of the strip takes its own slice of it.
private struct ExquisiteCorpseHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private typealias Timing = GameHubArtworkTiming

    private static let panelSize = CGSize(width: 126, height: 46)
    private static let parts: [ExquisiteCorpsePartKind] = [.head, .body, .legs]
    /// Where the first part starts, and how much of `progress` one part takes.
    private static let firstPart = 0.08
    private static let partStep = 0.17
    private static let finish = firstPart + partStep * Double(parts.count)

    private static let sparkles = [
        GameHubSparkle(size: 14, color: .paeoniaInkGold, x: 0.26, y: 0.5),
        GameHubSparkle(size: 9, color: .paeoniaTextPrimary, x: 0.72, y: 0.24),
        GameHubSparkle(size: 11, color: .paeoniaInkLavender, x: 0.76, y: 0.5),
        GameHubSparkle(size: 8, color: .paeoniaInkGold, x: 0.08, y: 0.4),
        GameHubSparkle(size: 10, color: .paeoniaTextPrimary, x: 0.93, y: 0.34),
    ]

    var body: some View {
        let glow = Timing.ease(progress, from: Self.finish - 0.04, to: Self.finish + 0.08)
        let hop = sin(Timing.ease(progress, from: Self.finish, to: Self.finish + 0.1) * .pi)
        ZStack {
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.35), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 120
            )
            .opacity(glow)
            GameHubSparkleField(sparkles: Self.sparkles, progress: progress, start: Self.finish)
            crayons
            hearts
            strip
                .offset(y: -8 * hop)
                // Clear of the chips at the top of the card and the fade into the card at the bottom.
                .padding(.top, PaeoniaSpacing.space24)
                .padding(.bottom, PaeoniaSpacing.space24)
        }
    }

    // MARK: Strip

    private var strip: some View {
        let creature = ExquisiteCorpseHubCreature(blink: blink, wave: wave)
        return VStack(spacing: 0) {
            ForEach(Self.parts, id: \.rawValue) { part in
                let start = Self.firstPart + Self.partStep * Double(part.rawValue)
                ExquisiteCorpseHubPanel(
                    part: part,
                    open: Timing.ease(progress, from: start, to: start + Self.partStep * 0.8),
                    creature: creature
                )
                .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            }
        }
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.6), radius: 16, y: 8)
        .rotationEffect(.degrees(-3))
    }

    /// The raised arm waves a few times after the hop and comes to rest.
    private var wave: Double {
        let start = Self.finish + 0.04
        let fraction = min(max((progress - start) / (0.98 - start), 0), 1)
        return 18 * sin(fraction * .pi * 4) * (1 - fraction)
    }

    /// One blink near the end.
    private var blink: Double {
        sin(Timing.ease(progress, from: Self.finish + 0.22, to: Self.finish + 0.28) * .pi)
    }

    // MARK: Crayons

    /// One crayon on each side, tips toward the paper. The left one draws the head
    /// and the feet, and the right one draws the sweater.
    private var crayons: some View {
        GeometryReader { proxy in
            crayon(color: .paeoniaAccentPrimary, tilt: 30, parts: [.head, .legs], delay: 0)
                .position(x: proxy.size.width * 0.15, y: proxy.size.height * 0.68)
            crayon(color: .paeoniaInkBlue, tilt: -26, parts: [.body], delay: 0.04)
                .position(x: proxy.size.width * 0.86, y: proxy.size.height * 0.7)
        }
    }

    private func crayon(
        color: Color,
        tilt: Double,
        parts: [ExquisiteCorpsePartKind],
        delay: Double
    ) -> some View {
        let pop = Timing.pop(progress, from: delay, to: delay + 0.1)
        let wiggle = parts.reduce(0.0) { total, part in
            let start = Self.firstPart + Self.partStep * Double(part.rawValue)
            let fraction = min(max((progress - start) / Self.partStep, 0), 1)
            return total + 8 * sin(fraction * .pi * 6)
        }
        return ExquisiteCorpseHubCrayon(color: color)
            .rotationEffect(.degrees(tilt + wiggle))
            .scaleEffect(0.3 + 0.7 * pop)
            .opacity(min(1, pop * 2))
    }

    // MARK: Hearts

    private var hearts: some View {
        GeometryReader { proxy in
            heart(size: 15, color: .paeoniaAccentSecondary, index: 0)
                .position(x: proxy.size.width * 0.3, y: proxy.size.height * 0.34)
            heart(size: 10, color: .paeoniaAccentPrimary, index: 1)
                .position(x: proxy.size.width * 0.23, y: proxy.size.height * 0.27)
        }
    }

    private func heart(size: CGFloat, color: Color, index: Int) -> some View {
        let begin = Self.finish + 0.06 + 0.05 * Double(index)
        let pop = Timing.pop(progress, from: begin, to: begin + 0.1)
        return Image(systemName: "heart.fill")
            .accessibilityHidden(true)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(index == 0 ? -12 : 10))
            .scaleEffect(0.3 + 0.7 * pop)
            .opacity(min(1, pop * 2))
            .offset(y: 6 * (1 - pop))
    }
}

/// One part of the strip, showing its band of the creature. It hangs from its top
/// edge and swings down from edge-on to flat. It is darker while it faces away, and
/// a dashed crease marks the fold under it.
private struct ExquisiteCorpseHubPanel: View {
    let part: ExquisiteCorpsePartKind
    /// From 0 (folded) to 1 (open).
    let open: Double
    let creature: ExquisiteCorpseHubCreature

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .top) {
                Rectangle().fill(.paeoniaWidgetDrawing)
                creature
                    .frame(width: size.width, height: size.height * 3)
                    .offset(y: -size.height * CGFloat(part.rawValue))
                    .frame(width: size.width, height: size.height, alignment: .top)
                Rectangle().fill(.paeoniaBackgroundSecondary.opacity(0.5 * (1 - open)))
            }
        }
        .overlay(alignment: .bottom) { crease }
        .clipShape(panelShape)
        .rotation3DEffect(.degrees((1 - open) * 90), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
        // Edge-on, a part is a thin line. It is not worth showing.
        .opacity(min(1, open * 6))
    }

    @ViewBuilder private var crease: some View {
        if part != .legs {
            ExquisiteCorpseHorizontalLine()
                .stroke(
                    Color.paeoniaTextInverse.opacity(0.25),
                    style: StrokeStyle(lineWidth: PaeoniaRadius.strokeDefault, dash: [4, 3])
                )
                .frame(height: PaeoniaRadius.strokeDefault)
                .background(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Color.paeoniaTextInverse.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                }
        }
    }

    /// Round only the outer corners of the strip.
    private var panelShape: UnevenRoundedRectangle {
        let isFirst = part == .head
        let isLast = part == .legs
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? PaeoniaRadius.radius12 : 0,
            bottomLeadingRadius: isLast ? PaeoniaRadius.radius12 : 0,
            bottomTrailingRadius: isLast ? PaeoniaRadius.radius12 : 0,
            topTrailingRadius: isFirst ? PaeoniaRadius.radius12 : 0,
            style: .continuous
        )
    }
}

/// A crayon, tip up, with a paper wrapper around its middle.
private struct ExquisiteCorpseHubCrayon: View {
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            ExquisiteCorpseHubCrayonTip()
                .fill(color)
                .frame(width: 12, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .overlay {
                    VStack(spacing: 3) {
                        Rectangle().fill(color).frame(height: 2)
                        Spacer(minLength: 0)
                        Rectangle().fill(color).frame(height: 2)
                    }
                    .padding(.vertical, 4)
                    .background(.paeoniaWidgetDrawing.opacity(0.85))
                    .frame(height: 30)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: 18, height: 56)
        }
        .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 6, x: 2, y: 4)
    }
}

/// The cone at the top of a crayon, with a rounded point.
private struct ExquisiteCorpseHubCrayonTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY + 2))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY + 2),
                control: CGPoint(x: rect.midX, y: rect.minY - 1)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

#if DEBUG
#Preview {
    ExquisiteCorpseHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
