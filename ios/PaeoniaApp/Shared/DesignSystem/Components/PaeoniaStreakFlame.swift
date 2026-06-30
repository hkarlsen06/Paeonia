import SwiftUI

/// A celebratory streak indicator: a flame that fills liquid-style from the
/// bottom up while the day count ticks toward its value, embers drift off the
/// top, and the haptics build to a payoff pop as it lands. It's the dopamine
/// moment for keeping a streak alive.
///
/// The component is purely presentational — pass the streak `count` and it plays
/// the count-up on appear. It is deliberately reusable: the answer-flow
/// completion screen uses it as a hero now, and a calmer `playsCelebration:
/// false` form is ready for a static surface (e.g. the Us-tab streak label,
/// `home.streak.label`) when that lands.
///
/// Everything is time-driven and deterministic (no external animation state), so
/// it renders the same every play and stays smooth. With Reduce Motion on, or
/// `playsCelebration: false`, it shows the final, full-flame state immediately
/// with a single light haptic instead of the build-up.
struct PaeoniaStreakFlame: View {
    let count: Int
    var playsCelebration: Bool = true
    /// A broken streak that can be bought back: the flame renders cold and dim
    /// (no fill, glow, embers, or celebration) so it reads as "slipped". The
    /// `count` is then the lost streak length the restore would bring back. The
    /// "get it back" action lives in the surrounding surface, not here.
    var isBroken: Bool = false
    /// Keeps the flame gently "alive" at rest — a breathing liquid level and the
    /// living flicker — without the count-up celebration or its haptics. For
    /// surfaces that show the streak on its own (e.g. the streak detail sheet),
    /// not the earn-it moment. Ignored while celebrating, broken, or Reduce Motion.
    var ambientMotion: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAnimating = false
    /// True while running the calm continuous motion (vs. the count-up celebration),
    /// so the timeline keeps the level high and breathing instead of filling from zero.
    @State private var isAmbient = false
    /// True while running the one-shot drain that turns a full flame into the cold,
    /// frozen broken pool when a slipped streak first appears.
    @State private var isBreaking = false
    @State private var hasStarted = false
    @State private var animationStart = Date()
    @State private var driver: Task<Void, Never>?
    /// The wave phase the drain settles on, so the static frozen pool matches the
    /// last animated frame instead of snapping to a different ripple.
    @State private var frozenPhase: CGFloat = 0

    // Payoff accents, nudged by the driver the instant the flame fills.
    @State private var flameScale: CGFloat = 1
    @State private var glowFlare: CGFloat = 0

    @ScaledMetric(relativeTo: .largeTitle) private var flameHeight: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 54

    /// How long the flame takes to fill and the number to reach `count`.
    private static let fillDuration: Double = 1.3
    /// How quickly the liquid surface ripples, in wave cycles per second.
    private static let waveSpeed: Double = 0.85
    /// At-rest motion: a high liquid level that breathes a little, so the flame keeps
    /// moving without reading as "filling up" again.
    private static let ambientLevel: CGFloat = 0.9
    private static let ambientBreath: CGFloat = 0.06
    private static let ambientBreathSpeed: Double = 0.8
    /// A slipped streak doesn't start broken — when the restore surface opens it
    /// drains from a full, warm flame down to the cold pool over this long.
    private static let breakDuration: Double = 1.6
    /// The flame begins full when it slips, then settles at the low frozen pool.
    private static let brokenStartLevel: CGFloat = 1
    private static let brokenLevel: CGFloat = 0.22
    /// The surface sloshes at this speed as it drains, easing to a standstill.
    private static let breakWaveSpeed: Double = 1.4

    private var flameWidth: CGFloat { flameHeight * 0.84 }

    var body: some View {
        content
            .onAppear(perform: start)
            .onDisappear { driver?.cancel() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    @ViewBuilder
    private var content: some View {
        if isAnimating {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(animationStart)
                if isBreaking {
                    breakingLayout(elapsed: elapsed)
                } else {
                    let phase = elapsed * Self.waveSpeed
                    let flicker = sin(elapsed * 6.3) * 0.5 + sin(elapsed * 11.7) * 0.2
                    // Ambient stays high and breathing with the number settled; the
                    // celebration fills from empty while the number climbs.
                    let level = isAmbient ? Self.ambientFillLevel(at: elapsed) : fillLevel(at: elapsed)
                    let value = isAmbient ? count : Int((Double(count) * Double(level)).rounded())

                    layout(level: level, phase: CGFloat(phase), flicker: CGFloat(flicker), value: value, emits: !isAmbient, brokenness: 0)
                }
            }
        } else {
            // Reduce Motion, a calm/static use, or the settled end of a drain: the
            // full settled flame, or the cold frozen pool once a streak has slipped.
            layout(
                level: isBroken ? Self.brokenLevel : 1,
                phase: isBroken ? frozenPhase : 0,
                flicker: 0,
                value: count,
                emits: false,
                brokenness: isBroken ? 1 : 0
            )
        }
    }

    /// One frame of the drain: the flame falls from full to the cold pool while the
    /// wave eases to a freeze and the warm color bleeds out to grey.
    private func breakingLayout(elapsed: TimeInterval) -> some View {
        let progress = CGFloat(smoothstep(min(elapsed / Self.breakDuration, 1)))
        let level = Self.brokenStartLevel + (Self.brokenLevel - Self.brokenStartLevel) * progress
        let phase = Self.breakPhase(at: elapsed)
        // The living flicker fades out as the flame goes still.
        let flicker = (sin(elapsed * 6.3) * 0.5 + sin(elapsed * 11.7) * 0.2) * Double(1 - progress)
        return layout(level: level, phase: phase, flicker: CGFloat(flicker), value: count, emits: false, brokenness: progress)
    }

    /// Renders a single flame frame. `brokenness` (0 alive → 1 slipped) crossfades
    /// the warm flame into the cold frozen pool, so the same layout serves the
    /// living flame, the static broken state, and every frame of the drain between.
    private func layout(level: CGFloat, phase: CGFloat, flicker: CGFloat, value: Int, emits: Bool, brokenness: CGFloat) -> some View {
        let alive = Double(1 - brokenness)
        return VStack(spacing: PaeoniaSpacing.space12) {
            flame(level: level, phase: phase, flicker: flicker, brokenness: brokenness)
                .frame(width: flameWidth, height: flameHeight)
                .overlay {
                    if emits {
                        StreakEmberField(start: animationStart)
                    }
                }
                .scaleEffect(flameScale)
                // The warm glow shrinks and fades out as the flame cools, with a
                // faint dark shadow fading in to anchor the spent pool.
                .shadow(
                    color: .paeoniaAccentPrimary.opacity((0.4 + 0.4 * Double(glowFlare)) * alive),
                    radius: (22 + 26 * glowFlare) * (1 - brokenness) + 8 * brokenness
                )
                .shadow(color: .black.opacity(0.18 * Double(brokenness)), radius: 8)
                .shadow(color: .paeoniaAccentSecondary.opacity(0.35 * Double(glowFlare) * alive), radius: 10)

            VStack(spacing: PaeoniaSpacing.space4) {
                Text(verbatim: value.formatted())
                    .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.paeoniaTextPrimary.mix(with: .paeoniaTextSecondary, by: Double(brokenness)))
                    .overlay { strikethrough(brokenness: brokenness) }

                Text(.homeStreakLabel)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Color.paeoniaAccentPrimary.mix(with: .paeoniaTextTertiary, by: Double(brokenness)))
            }
        }
    }

    /// The cross-out struck through the streak number when it has slipped. It draws
    /// on from the leading edge as the flame drains and sits fully drawn once frozen,
    /// so the lost count reads as cancelled. Healthy flames pass `brokenness: 0`, so
    /// the line scales to nothing and stays hidden.
    private func strikethrough(brokenness: CGFloat) -> some View {
        Capsule()
            .fill(Color.paeoniaTextSecondary)
            .frame(height: max(numberSize * 0.07, 2))
            .scaleEffect(x: brokenness, y: 1, anchor: .leading)
    }

    private func flame(level: CGFloat, phase: CGFloat, flicker: CGFloat, brokenness: CGFloat) -> some View {
        let alive = Double(1 - brokenness)
        return ZStack {
            aura(level: level)
                .opacity(alive)

            // The empty flame: a dim vessel waiting to be filled.
            FlameShape().fill(Self.emptyFlameStyle)

            // The rising liquid, clipped to the flame outline. As a streak slips the
            // warm fill drains and cools, the cold pool crossfading in over it.
            StreakLiquidShape(level: level, phase: phase)
                .fill(Self.liquidStyle)
                .clipShape(FlameShape())
                .opacity(alive)

            StreakLiquidShape(level: level, phase: phase)
                .fill(Self.brokenLiquidStyle)
                .clipShape(FlameShape())
                .opacity(Double(brokenness))

            // A bright rim so the flame edge reads against the plum surface,
            // dimming to a cold edge as it breaks.
            FlameShape().stroke(Self.rimStyle, lineWidth: PaeoniaRadius.strokeEmphasis)
                .opacity(alive)
            FlameShape().stroke(Self.brokenRimStyle, lineWidth: PaeoniaRadius.strokeEmphasis)
                .opacity(Double(brokenness))
        }
        // A faint living flicker — wider/shorter then back — anchored at the base.
        // It fades out as the flame freezes, so a settled broken flame is still.
        .scaleEffect(x: 1 + flicker * 0.02, y: 1 - flicker * 0.015, anchor: .bottom)
    }

    /// A soft glow behind the flame that brightens as it fills.
    private func aura(level: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.paeoniaAccentPrimary.opacity(0.1 + 0.35 * level), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: flameWidth * 0.75
                )
            )
            .scaleEffect(1.35)
            .blur(radius: 6)
    }

    private static let emptyFlameStyle = LinearGradient(
        colors: [.paeoniaSurfacePressed.opacity(0.9), .paeoniaSurfaceSecondary.opacity(0.65)],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let liquidStyle = LinearGradient(
        colors: [.paeoniaAccentPrimary, .paeoniaAccentSecondary, .paeoniaInkGold],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let rimStyle = LinearGradient(
        colors: [.paeoniaAccentPrimary.opacity(0.95), .paeoniaInkGold.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let brokenLiquidStyle = LinearGradient(
        colors: [.paeoniaTextSecondary.opacity(0.5), .paeoniaSurfacePressed.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let brokenRimStyle = LinearGradient(
        colors: [.paeoniaTextSecondary.opacity(0.55), .paeoniaSurfaceSecondary.opacity(0.5)],
        startPoint: .top,
        endPoint: .bottom
    )

    private var accessibilityLabel: String {
        "\(count) \(String(localized: .homeStreakLabel))"
    }

    // MARK: - Sequence

    private func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let celebrates = playsCelebration && !reduceMotion && !isBroken && count >= 1
        if celebrates {
            animationStart = Date()
            isAmbient = false
            isAnimating = true
            driver = Task { @MainActor in
                await runCountUp()
            }
            return
        }

        // A slipped streak drains from a full, warm flame down to the cold frozen
        // pool when the restore surface opens, instead of appearing already broken.
        let breaks = isBroken && !reduceMotion && count >= 1
        if breaks {
            animationStart = Date()
            isBreaking = true
            isAnimating = true
            driver = Task { @MainActor in
                await runBreak()
            }
            return
        }

        // A calm, continuously "alive" flame for at-rest surfaces: no count-up and
        // no haptics, just the breathing liquid and the living flicker.
        let ambient = ambientMotion && !reduceMotion && !isBroken && count >= 1
        if ambient {
            animationStart = Date()
            isAmbient = true
            isAnimating = true
            return
        }

        isAnimating = false
        // A broken streak is not a celebration, so it stays silent.
        if playsCelebration, !isBroken {
            PaeoniaHaptics.streakContinued()
        }
    }

    /// Fires the rising soft ticks in step with the climbing number, then the
    /// payoff hit and a quick flare the instant the flame tops out.
    @MainActor
    private func runCountUp() async {
        let pulseCount = min(max(count, 1), 14)
        var lastTime = 0.0

        for index in 0..<pulseCount {
            let fraction = pulseCount == 1 ? 1 : Double(index) / Double(pulseCount - 1)
            // Match the fill's smoothstep so ticks land with the number.
            let targetTime = Self.fillDuration * smoothstep(fraction) * 0.95
            let gap = targetTime - lastTime
            if gap > 0, await sleep(gap) == false { return }
            lastTime = targetTime

            PaeoniaHaptics.streakTick(intensity: 0.32 + 0.5 * fraction)
        }

        let remainder = Self.fillDuration - lastTime
        if remainder > 0, await sleep(remainder) == false { return }

        PaeoniaHaptics.streakCelebrated()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.45)) {
            flameScale = 1.14
            glowFlare = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.16)) {
            flameScale = 1
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.12)) {
            glowFlare = 0
        }
    }

    /// Holds the drain on screen for its full duration, then settles the flame into
    /// the static frozen pool so the timeline can stop redrawing.
    @MainActor
    private func runBreak() async {
        frozenPhase = Self.breakPhase(at: Self.breakDuration)
        try? await Task.sleep(for: .seconds(Self.breakDuration))
        guard !Task.isCancelled else { return }
        isBreaking = false
        isAnimating = false
    }

    /// The wave phase during the drain. The surface sloshes at `breakWaveSpeed` and
    /// eases to a standstill by `breakDuration`, freezing the liquid mid-ripple.
    private static func breakPhase(at elapsed: TimeInterval) -> CGFloat {
        let time = min(elapsed, breakDuration)
        // Integral of a speed that decays linearly from breakWaveSpeed to zero.
        return CGFloat(breakWaveSpeed * (time - time * time / (2 * breakDuration)))
    }

    private func fillLevel(at elapsed: TimeInterval) -> CGFloat {
        CGFloat(smoothstep(min(elapsed / Self.fillDuration, 1)))
    }

    /// The at-rest liquid level: high, with a slow gentle breath so the flame stays
    /// alive without re-filling.
    private static func ambientFillLevel(at elapsed: TimeInterval) -> CGFloat {
        ambientLevel + ambientBreath * CGFloat(sin(elapsed * ambientBreathSpeed))
    }

    /// Sleeps for `seconds`, returning `false` if the count-up was cancelled.
    private func sleep(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

// MARK: - Shapes

/// A symmetric flame/teardrop with a pointed tip and a rounded base, drawn in the
/// view's rect so it scales with the surrounding frame.
struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: point(0.5, 0))
        path.addCurve(to: point(0.92, 0.55), control1: point(0.6, 0.16), control2: point(0.92, 0.34))
        path.addCurve(to: point(0.5, 1), control1: point(0.92, 0.82), control2: point(0.7, 1))
        path.addCurve(to: point(0.08, 0.55), control1: point(0.3, 1), control2: point(0.08, 0.82))
        path.addCurve(to: point(0.5, 0), control1: point(0.08, 0.34), control2: point(0.4, 0.16))
        path.closeSubpath()
        return path
    }
}

/// The liquid inside the flame: everything below a sine-wave surface sitting at
/// `level` (0 empty, 1 full). The surface ripples with `phase` and flattens as it
/// fills, so a full flame reads as settled rather than sloshing.
struct StreakLiquidShape: Shape {
    var level: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedLevel = min(max(level, 0), 1)
        let surfaceY = rect.maxY - rect.height * clampedLevel
        let amplitude = rect.height * 0.03 * (1 - clampedLevel * 0.7)
        let steps = 26

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: surfaceY))
        for step in 0...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let x = rect.minX + rect.width * fraction
            let y = surfaceY + sin((fraction * 2 + phase) * .pi * 2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Embers

/// A small, deterministic field of glints that rise from the flame and fade out,
/// drawn with `Canvas` so it stays smooth and seeded by index so every play looks
/// the same.
private struct StreakEmberField: View {
    let start: Date

    private static let emberCount = 14

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                draw(in: &context, size: size, elapsed: elapsed)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        for index in 0..<Self.emberCount {
            let seed = Double(index)
            let period = 1.6 + rand(seed, 3.1) * 1.4
            // Each ember loops on its own offset so they don't pulse in unison.
            let loop = (elapsed + rand(seed, 7.7) * period).truncatingRemainder(dividingBy: period) / period
            let fade = sin(loop * .pi)

            guard fade > 0.01 else { continue }

            let drift = sin(loop * .pi * 2 + seed) * 0.06
            let x = size.width * (0.5 + (rand(seed, 11.3) - 0.5) * 0.5 + drift)
            let y = size.height * (0.92 - loop * 0.9)
            let radius = 1 + rand(seed, 5.5) * 1.7
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            context.fill(Path(ellipseIn: rect), with: .color(emberColor(index).opacity(0.7 * fade)))
        }
    }

    private func emberColor(_ index: Int) -> Color {
        switch index % 3 {
        case 0: .paeoniaAccentPrimary
        case 1: .paeoniaInkGold
        default: .paeoniaAccentSecondary
        }
    }

    /// Deterministic pseudo-random value in `0...1` from a seed and a salt.
    private func rand(_ seed: Double, _ salt: Double) -> Double {
        let value = sin(seed * salt + salt) * 43_758.5453
        return value - floor(value)
    }
}

#if DEBUG
#Preview("Count up") {
    PaeoniaStreakFlame(count: 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Big streak") {
    PaeoniaStreakFlame(count: 128)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Static (settled)") {
    PaeoniaStreakFlame(count: 7, playsCelebration: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
