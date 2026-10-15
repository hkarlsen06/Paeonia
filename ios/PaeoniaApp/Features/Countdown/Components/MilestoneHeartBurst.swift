import SwiftUI

/// The hearts that float up off the countdown calendar's page on the day of an event. The
/// burst sits behind the page's "Today", so the hearts come out from behind the word and
/// rise past the top of the calendar while they fade. It is sized from the page's height
/// (`unit`) and plays once each time it appears, in about 1.3 seconds. Under Reduce Motion
/// it is one small still heart above the word.
struct MilestoneHeartBurst: View {
    let unit: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flips once on appear to start every heart's keyframes.
    @State private var isLaunched = false

    var body: some View {
        ZStack {
            if reduceMotion {
                Image(systemName: "heart.fill")
                    .font(.system(size: unit * 0.2, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentSecondary)
                    .accessibilityHidden(true)
                    .offset(y: -unit * 0.42)
            } else {
                ForEach(Self.particles.indices, id: \.self) { index in
                    particle(Self.particles[index])
                }
            }
        }
        .onAppear { isLaunched = true }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func particle(_ particle: Particle) -> some View {
        Image(systemName: particle.symbol)
            .font(.system(size: unit * particle.size, weight: .semibold))
            .foregroundStyle(particle.color)
            .accessibilityHidden(true)
            .shadow(color: .black.opacity(0.18), radius: unit * 0.03, y: unit * 0.02)
            .keyframeAnimator(initialValue: Flight(), trigger: isLaunched) { content, flight in
                let angle = particle.angle * .pi / 180
                let reach = unit * particle.distance * flight.travel
                content
                    .scaleEffect(flight.scale)
                    .rotationEffect(.degrees(particle.spin * flight.travel))
                    .offset(
                        x: cos(angle) * reach,
                        y: sin(angle) * reach - unit * 0.3 * flight.rise
                    )
                    .opacity(flight.opacity)
            } keyframes: { _ in
                // Each track runs 1.15 seconds after the particle's delay, so the last
                // particle is gone at 1.3 seconds.
                KeyframeTrack(\.travel) {
                    LinearKeyframe(0, duration: particle.delay)
                    SpringKeyframe(1, duration: 1.15, spring: Spring(duration: 0.9, bounce: 0))
                }
                KeyframeTrack(\.rise) {
                    LinearKeyframe(0, duration: particle.delay)
                    LinearKeyframe(1, duration: 1.15)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.3, duration: particle.delay)
                    SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                    LinearKeyframe(1, duration: 0.45)
                    LinearKeyframe(0.75, duration: 0.4)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: particle.delay)
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: 0.62)
                    CubicKeyframe(0, duration: 0.45)
                }
            }
    }
}

private extension MilestoneHeartBurst {
    /// One heart or sparkle. Angles are in degrees, where -90 is straight up. Distance and
    /// size are shares of `unit`. Delays stay under 0.15 seconds so the last heart is gone
    /// before the card takes the burst away at 1.4 seconds.
    struct Particle {
        let symbol: String
        let color: Color
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let delay: Double
        let spin: Double

        init(
            _ symbol: String,
            _ color: Color,
            _ angle: Double,
            _ distance: CGFloat,
            _ size: CGFloat,
            _ delay: Double,
            _ spin: Double
        ) {
            self.symbol = symbol
            self.color = color
            self.angle = angle
            self.distance = distance
            self.size = size
            self.delay = delay
            self.spin = spin
        }
    }

    /// Where a particle is along its flight. `travel` carries it out along its angle,
    /// `rise` floats it up a little more the whole time.
    struct Flight {
        var travel: CGFloat = 0
        var rise: CGFloat = 0
        var scale: CGFloat = 0.2
        var opacity: Double = 0
    }

    /// Mostly hearts in an uneven upward fan, with a few gold sparkles between. The side
    /// ones travel far enough to clear the calendar's edges. Columns: symbol, color, angle,
    /// distance, size, delay, spin.
    static let particles: [Particle] = [
        Particle("heart.fill", .paeoniaAccentSecondary, -96, 1.45, 0.22, 0, -8),
        Particle("heart.fill", .paeoniaAccentPrimary, -120, 1.3, 0.17, 0.05, -20),
        Particle("heart.fill", .paeoniaAccentPrimary, -68, 1.35, 0.18, 0.03, 16),
        Particle("heart.fill", .paeoniaAccentSecondary, -142, 1.25, 0.14, 0.09, -26),
        Particle("heart.fill", .paeoniaAccentSecondary, -42, 1.3, 0.15, 0.11, 24),
        Particle("heart.fill", .paeoniaAccentPrimary, -164, 1.15, 0.12, 0.14, -30),
        Particle("heart.fill", .paeoniaAccentPrimary, -17, 1.2, 0.12, 0.07, 30),
        Particle("heart.fill", .paeoniaAccentSecondary, -82, 1.6, 0.11, 0.13, 12),
        Particle("heart.fill", .paeoniaAccentPrimary, -108, 1.6, 0.1, 0.1, -12),
        Particle("sparkle", .paeoniaInkGold, -130, 1.5, 0.12, 0.06, 60),
        Particle("sparkle", .paeoniaInkGold, -55, 1.55, 0.11, 0.12, -60),
        Particle("sparkle", .paeoniaInkGold, -28, 1.1, 0.09, 0.02, 40),
    ]
}

#if DEBUG
#Preview {
    MilestoneHeartBurst(unit: 90)
        .frame(width: 200, height: 200)
        .background(.paeoniaBackgroundPrimary)
}
#endif
