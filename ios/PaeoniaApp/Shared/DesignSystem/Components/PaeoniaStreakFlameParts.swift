import SwiftUI

// MARK: - Motion

/// Timing and curves for the streak flame. Every value is a pure function of
/// elapsed time, so each play looks the same.
enum StreakFlameMotion {
    /// How long the flame takes to fill and the number to reach its count.
    static let fillDuration: Double = 1.3
    /// How quickly the liquid surface ripples, in wave cycles per second.
    static let waveSpeed: Double = 0.85
    /// At-rest motion: a high liquid level that breathes a little, so the flame keeps
    /// moving without reading as "filling up" again.
    static let ambientBaseLevel: CGFloat = 0.9
    static let ambientBreath: CGFloat = 0.06
    static let ambientBreathSpeed: Double = 0.8
    /// A slipped streak doesn't start broken. When the restore surface opens it
    /// drains from a full, warm flame down to the cold pool over this long.
    static let breakDuration: Double = 1.6
    /// The flame begins full when it slips, then settles at the low frozen pool.
    static let brokenStartLevel: CGFloat = 1
    static let brokenLevel: CGFloat = 0.22
    /// The surface sloshes at this speed as it drains, easing to a standstill.
    static let breakWaveSpeed: Double = 1.4

    static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    static func fillLevel(at elapsed: TimeInterval) -> CGFloat {
        CGFloat(smoothstep(min(elapsed / fillDuration, 1)))
    }

    /// The at-rest liquid level: high, with a slow gentle breath so the flame stays
    /// alive without re-filling.
    static func ambientLevel(at elapsed: TimeInterval) -> CGFloat {
        ambientBaseLevel + ambientBreath * CGFloat(sin(elapsed * ambientBreathSpeed))
    }

    /// The faint living flicker, a slightly wider and shorter flame then back.
    static func flicker(at elapsed: TimeInterval) -> CGFloat {
        CGFloat(sin(elapsed * 6.3) * 0.5 + sin(elapsed * 11.7) * 0.2)
    }

    /// The wave phase during the drain. The surface sloshes at `breakWaveSpeed` and
    /// eases to a standstill by `breakDuration`, freezing the liquid mid-ripple.
    static func breakPhase(at elapsed: TimeInterval) -> CGFloat {
        let time = min(elapsed, breakDuration)
        // Integral of a speed that decays linearly from breakWaveSpeed to zero.
        return CGFloat(breakWaveSpeed * (time - time * time / (2 * breakDuration)))
    }
}

// MARK: - Styles

enum StreakFlameStyle {
    /// The empty flame: a dim vessel waiting to be filled.
    static let empty = LinearGradient(
        colors: [.paeoniaSurfacePressed.opacity(0.9), .paeoniaSurfaceSecondary.opacity(0.65)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let liquid = LinearGradient(
        colors: [.paeoniaAccentPrimary, .paeoniaAccentSecondary, .paeoniaInkGold],
        startPoint: .top,
        endPoint: .bottom
    )

    static let rim = LinearGradient(
        colors: [.paeoniaAccentPrimary.opacity(0.95), .paeoniaInkGold.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let brokenLiquid = LinearGradient(
        colors: [.paeoniaTextSecondary.opacity(0.5), .paeoniaSurfacePressed.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let brokenRim = LinearGradient(
        colors: [.paeoniaTextSecondary.opacity(0.55), .paeoniaSurfaceSecondary.opacity(0.5)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Flame art

/// The flame vessel, its liquid, and the glow behind it for one frame.
/// `brokenness` (0 alive, 1 slipped) crossfades the warm flame into the cold pool.
struct StreakFlameArt: View {
    let level: CGFloat
    let phase: CGFloat
    let flicker: CGFloat
    let brokenness: CGFloat
    /// Width of the frame this is drawn in. Sizes the glow.
    let width: CGFloat

    var body: some View {
        let alive = Double(1 - brokenness)
        let cold = Double(brokenness)
        ZStack {
            aura
                .opacity(alive)

            FlameShape().fill(StreakFlameStyle.empty)

            // The rising liquid, clipped to the flame outline. As a streak slips the
            // warm fill drains and cools, the cold pool crossfading in over it.
            StreakLiquidShape(level: level, phase: phase)
                .fill(StreakFlameStyle.liquid)
                .clipShape(FlameShape())
                .opacity(alive)

            StreakLiquidShape(level: level, phase: phase)
                .fill(StreakFlameStyle.brokenLiquid)
                .clipShape(FlameShape())
                .opacity(cold)

            // A bright rim so the flame edge reads against the plum surface,
            // dimming to a cold edge as it breaks.
            FlameShape().stroke(StreakFlameStyle.rim, lineWidth: PaeoniaRadius.strokeEmphasis)
                .opacity(alive)
            FlameShape().stroke(StreakFlameStyle.brokenRim, lineWidth: PaeoniaRadius.strokeEmphasis)
                .opacity(cold)
        }
        // A faint living flicker, wider and shorter then back, anchored at the base.
        // It fades out as the flame freezes, so a settled broken flame is still.
        .scaleEffect(x: 1 + flicker * 0.02, y: 1 - flicker * 0.015, anchor: .bottom)
    }

    /// A soft glow behind the flame that brightens as it fills.
    private var aura: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.paeoniaAccentPrimary.opacity(0.1 + 0.35 * level), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.75
                )
            )
            .scaleEffect(1.35)
            .blur(radius: 6)
    }
}

// MARK: - Shapes

/// A symmetric flame/teardrop with a pointed tip and a rounded base, drawn in the
/// view's rect so it scales with the surrounding frame.
nonisolated struct FlameShape: Shape {
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
nonisolated struct StreakLiquidShape: Shape {
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
/// the same. It loops until its parent removes it.
struct StreakEmberField: View {
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
