import Foundation
import SwiftUI

/// A deterministic, time-driven particle field that swirls inward toward the
/// heart, then bursts outward at the climax. Drawn entirely with `Canvas` so it
/// stays smooth and previewable, and seeded by index so every play looks the same.
struct PairingCelebrationParticleField: View { // swiftlint:disable:this type_body_length
    let start: Date

    private static let particleCount = 150

    private struct ParticleDrawState {
        let elapsed: TimeInterval
        let absorb: Double
        let explode: Double
        let appear: Double
    }

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
        guard elapsed < PairingCelebrationTiming.explodeEnd else {
            return
        }

        let center = CGPoint(
            x: size.width / 2,
            y: size.height * PairingCelebrationTiming.centerYRatio
        )
        let maxRadius = min(size.width, size.height) * 0.62

        let absorb = progress(
            elapsed,
            from: PairingCelebrationTiming.absorbStart,
            over: PairingCelebrationTiming.absorb
        )
        let explode = progress(
            elapsed,
            from: PairingCelebrationTiming.explodeStart,
            over: PairingCelebrationTiming.explode
        )
        let appear = progress(elapsed, from: 0, over: PairingCelebrationTiming.heartAppear)

        drawGravityGlow(in: &context, center: center, absorb: absorb, explode: explode)
        drawParticles(
            in: &context,
            center: center,
            maxRadius: maxRadius,
            state: ParticleDrawState(
                elapsed: elapsed,
                absorb: absorb,
                explode: explode,
                appear: appear
            )
        )
        drawExplosionFlash(in: &context, center: center, maxRadius: maxRadius, explode: explode)
    }

    // MARK: Particles

    private func drawParticles(
        in context: inout GraphicsContext,
        center: CGPoint,
        maxRadius: CGFloat,
        state: ParticleDrawState
    ) {
        let sampleCount = 6
        for index in 0..<Self.particleCount {
            let seed = Double(index)
            let size = 2.4 + rand(seed, 3.71) * 4.0
            let now = state.explode > 0 ? state.explode : state.absorb
            let span = state.explode > 0 ? 0.08 : 0.09
            let opacity = state.explode > 0
                ? (1 - easeOut(state.explode)) * (0.55 + rand(seed, 17.3) * 0.45)
                : (0.18 + easeInOut(state.absorb) * 0.82) * state.appear

            guard opacity > 0.01 else {
                continue
            }

            // Sample the particle's recent path so the trail curves along the
            // spiral instead of cutting a straight chord behind it.
            var trail: [CGPoint] = []
            trail.reserveCapacity(sampleCount)
            for step in 0..<sampleCount {
                let fraction = Double(step) / Double(sampleCount - 1)
                let sampled = max(0, now - span * (1 - fraction))
                let point = state.explode > 0
                    ? explodePosition(seed: seed, center: center, maxRadius: maxRadius, progress: sampled)
                    : absorbPosition(
                        seed: seed,
                        center: center,
                        maxRadius: maxRadius,
                        progress: sampled,
                        elapsed: state.elapsed
                    )
                trail.append(point)
            }

            drawTrail(
                in: &context,
                points: trail,
                color: particleColor(for: index),
                opacity: opacity,
                size: size
            )
        }
    }

    /// Draws one particle as a curved, tapered trail of segments following its
    /// sampled path — fainter and thinner at the tail, brightest at the head, with
    /// a solid head dot. The trail reads as motion blur and makes the swirl and the
    /// outward burst obvious.
    private func drawTrail(
        in context: inout GraphicsContext,
        points: [CGPoint],
        color: Color,
        opacity: Double,
        size: CGFloat
    ) {
        guard let head = points.last, points.count > 1 else {
            return
        }

        for index in 1..<points.count {
            let nearHead = Double(index) / Double(points.count - 1)
            var segment = Path()
            segment.move(to: points[index - 1])
            segment.addLine(to: points[index])
            context.stroke(
                segment,
                with: .color(color.opacity(opacity * 0.6 * nearHead)),
                style: StrokeStyle(lineWidth: size * (0.25 + 0.55 * nearHead), lineCap: .round)
            )
        }

        let dot = CGRect(x: head.x - size / 2, y: head.y - size / 2, width: size, height: size)
        context.fill(Path(ellipseIn: dot), with: .color(color.opacity(opacity)))
    }

    /// Position while being pulled inward: the radius collapses toward the core
    /// and the swirl tightens (spins faster) as the particle nears the center, so
    /// the heart reads as having gravity.
    private func absorbPosition(
        seed: Double,
        center: CGPoint,
        maxRadius: CGFloat,
        progress: Double,
        elapsed: Double
    ) -> CGPoint {
        let eased = easeInOut(min(max(progress, 0), 1))
        let baseAngle = rand(seed, 11.13) * 2 * .pi
        let direction: Double = rand(seed, 19.91) > 0.5 ? 1 : -1
        let baseRadius = maxRadius * (0.35 + rand(seed, 7.17) * 0.6)

        let ambient = elapsed * 0.55 * direction
        let swirl = eased * (2.4 + rand(seed, 23.7) * 2.4) * direction * (1 + 1.8 * eased)
        let radius = baseRadius * pow(1 - eased, 1.7) + 9
        let angle = baseAngle + ambient + swirl

        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius * 0.82
        )
    }

    /// Position during the burst: particles fly outward from where they were, with
    /// a little spread so the explosion is not a perfect ring.
    private func explodePosition(
        seed: Double,
        center: CGPoint,
        maxRadius: CGFloat,
        progress: Double
    ) -> CGPoint {
        let eased = easeOut(min(max(progress, 0), 1))
        let baseAngle = rand(seed, 11.13) * 2 * .pi
        let spread = (rand(seed, 31.1) - 0.5) * 0.5
        let distance = maxRadius * (0.5 + rand(seed, 5.31) * 0.75)
        let radius = 9 + pow(eased, 0.6) * distance
        let angle = baseAngle + spread

        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius * 0.82
        )
    }

    // MARK: Glow & flash

    private func drawGravityGlow(
        in context: inout GraphicsContext,
        center: CGPoint,
        absorb: Double,
        explode: Double
    ) {
        guard explode <= 0 else {
            return
        }

        let intensity = easeInOut(absorb)
        let radius = 28 + intensity * 96
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let gradient = Gradient(colors: [
            Color.paeoniaAccentPrimary.opacity(0.08 + 0.45 * intensity),
            .clear
        ])

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        )
    }

    private func drawExplosionFlash(
        in context: inout GraphicsContext,
        center: CGPoint,
        maxRadius: CGFloat,
        explode: Double
    ) {
        guard explode > 0 else {
            return
        }

        let eased = easeOut(explode)

        // Bright central flash at the very start of the burst.
        if explode < 0.35 {
            let flashFade = 1 - explode / 0.35
            let flashRadius = 24 + eased * 130
            let rect = CGRect(
                x: center.x - flashRadius,
                y: center.y - flashRadius,
                width: flashRadius * 2,
                height: flashRadius * 2
            )
            let gradient = Gradient(colors: [
                Color.paeoniaTextPrimary.opacity(0.55 * flashFade),
                Color.paeoniaAccentPrimary.opacity(0.3 * flashFade),
                .clear
            ])
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: flashRadius)
            )
        }

        // A shockwave ring expanding outward.
        let ringRadius = eased * maxRadius
        let ringRect = CGRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        )
        context.stroke(
            Path(ellipseIn: ringRect),
            with: .color(.paeoniaAccentPrimary.opacity((1 - eased) * 0.6)),
            lineWidth: 1 + 5 * (1 - eased)
        )
    }

    // MARK: Helpers

    private func particleColor(for index: Int) -> Color {
        switch index % 4 {
        case 0:
            .paeoniaAccentPrimary
        case 1:
            .paeoniaAccentSecondary
        case 2:
            .paeoniaPartnerTwo
        default:
            .paeoniaTextPrimary
        }
    }

    private func progress(_ elapsed: TimeInterval, from begin: Double, over duration: Double) -> Double {
        guard duration > 0 else {
            return elapsed >= begin ? 1 : 0
        }
        return min(max((elapsed - begin) / duration, 0), 1)
    }

    private func easeInOut(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func easeOut(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return 1 - pow(1 - clamped, 2)
    }

    /// Deterministic pseudo-random value in `0...1` from a seed and a salt.
    private func rand(_ seed: Double, _ salt: Double) -> Double {
        let x = sin(seed * salt + salt) * 43_758.5453
        return x - floor(x)
    }
}
