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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAnimating = false
    @State private var hasStarted = false
    @State private var animationStart = Date()
    @State private var driver: Task<Void, Never>?

    // Payoff accents, nudged by the driver the instant the flame fills.
    @State private var flameScale: CGFloat = 1
    @State private var glowFlare: CGFloat = 0

    @ScaledMetric(relativeTo: .largeTitle) private var flameHeight: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 54

    /// How long the flame takes to fill and the number to reach `count`.
    private static let fillDuration: Double = 1.3
    /// How quickly the liquid surface ripples, in wave cycles per second.
    private static let waveSpeed: Double = 0.85

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
                let level = fillLevel(at: elapsed)
                let phase = elapsed * Self.waveSpeed
                let flicker = sin(elapsed * 6.3) * 0.5 + sin(elapsed * 11.7) * 0.2
                let value = Int((Double(count) * Double(level)).rounded())

                layout(level: level, phase: CGFloat(phase), flicker: CGFloat(flicker), value: value, emits: true)
            }
        } else {
            // Reduce Motion, or a calm/static use: the full, settled flame.
            layout(level: 1, phase: 0, flicker: 0, value: count, emits: false)
        }
    }

    private func layout(level: CGFloat, phase: CGFloat, flicker: CGFloat, value: Int, emits: Bool) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            flame(level: level, phase: phase, flicker: flicker)
                .frame(width: flameWidth, height: flameHeight)
                .overlay {
                    if emits {
                        StreakEmberField(start: animationStart)
                    }
                }
                .scaleEffect(flameScale)
                .shadow(color: .paeoniaAccentPrimary.opacity(0.4 + 0.4 * glowFlare), radius: 22 + 26 * glowFlare)
                .shadow(color: .paeoniaAccentSecondary.opacity(0.35 * glowFlare), radius: 10)

            VStack(spacing: PaeoniaSpacing.space4) {
                Text(verbatim: value.formatted())
                    .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.homeStreakLabel)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(.paeoniaAccentPrimary)
            }
        }
    }

    private func flame(level: CGFloat, phase: CGFloat, flicker: CGFloat) -> some View {
        ZStack {
            aura(level: level)

            // The empty flame: a dim vessel waiting to be filled.
            FlameShape().fill(Self.emptyFlameStyle)

            // The rising liquid, clipped to the flame outline.
            StreakLiquidShape(level: level, phase: phase)
                .fill(Self.liquidStyle)
                .clipShape(FlameShape())

            // A bright rim so the flame edge reads against the plum surface.
            FlameShape().stroke(Self.rimStyle, lineWidth: PaeoniaRadius.strokeEmphasis)
        }
        // A faint living flicker — wider/shorter then back — anchored at the base.
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

    private var accessibilityLabel: String {
        "\(count) \(String(localized: .homeStreakLabel))"
    }

    // MARK: - Sequence

    private func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let animates = playsCelebration && !reduceMotion && count >= 1
        guard animates else {
            isAnimating = false
            if playsCelebration {
                PaeoniaHaptics.streakContinued()
            }
            return
        }

        animationStart = Date()
        isAnimating = true
        driver = Task { @MainActor in
            await runCountUp()
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

    private func fillLevel(at elapsed: TimeInterval) -> CGFloat {
        CGFloat(smoothstep(min(elapsed / Self.fillDuration, 1)))
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
