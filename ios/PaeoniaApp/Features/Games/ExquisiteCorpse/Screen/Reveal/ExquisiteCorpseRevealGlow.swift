import SwiftUI

/// The soft light behind the whole figure. It rises to `level`, and when `pulse`
/// turns on, as the petals fly, it swells for a moment and settles back.
struct ExquisiteCorpseRevealGlow: View {
    /// The resting strength, from 0 to 1.
    let level: Double
    /// Swells the glow each time it changes.
    let pulse: Bool
    /// The middle of the whole figure, in the stage.
    let center: CGPoint
    /// The side of one part when the whole figure shows. The light starts around it.
    let fitSide: CGFloat
    /// How far the light reaches. It has faded out by then.
    let reach: CGFloat

    static let restingLevel = 0.16
    static let peakLevel = 0.30

    var body: some View {
        RadialGradient(
            colors: [.paeoniaAccentPrimary, .clear],
            center: .center,
            startRadius: fitSide * 0.35,
            endRadius: reach
        )
        .frame(width: reach * 2, height: reach * 2)
        .keyframeAnimator(initialValue: 1.0, trigger: pulse) { content, swell in
            content.opacity(level * swell)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(Self.peakLevel / Self.restingLevel, duration: PaeoniaMotion.motionSlow)
                CubicKeyframe(1, duration: PaeoniaMotion.motionMorph)
            }
        }
        .animation(PaeoniaMotion.celebrationReveal, value: level)
        .position(center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
