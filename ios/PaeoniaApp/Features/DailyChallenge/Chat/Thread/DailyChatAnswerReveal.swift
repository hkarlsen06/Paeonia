import SwiftUI

extension View {
    /// Plays the partner's answer arriving in the chat right after the user answered.
    /// Apply it to the bubble itself, not its full-width row, so the effects hug the bubble.
    func dailyChatAnswerReveal(isActive: Bool, seed: String) -> some View {
        modifier(DailyChatAnswerReveal(isActive: isActive, seed: seed))
    }
}

/// The bubble starts hidden behind a blur while two soft taps build up. Then it springs
/// in with a firm tap and a success haptic, a gold glow, sparkles around its edge, and a
/// petal burst. Reduce Motion shows the bubble at once and keeps the landing haptic.
private struct DailyChatAnswerReveal: ViewModifier {
    private static let buildUpStep: Duration = .milliseconds(120)

    let isActive: Bool
    let seed: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHidden: Bool
    @State private var burstStart: Date?
    @State private var landCount = 0

    init(isActive: Bool, seed: String) {
        self.isActive = isActive
        self.seed = seed
        // Hidden from the first frame, so the bubble never flashes before the reveal.
        _isHidden = State(initialValue: isActive)
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: isHidden ? 14 : 0)
            // The partner's bubble sits on the leading side and grows out of that corner.
            .scaleEffect(isHidden ? 0.72 : 1, anchor: .bottomLeading)
            .opacity(isHidden ? 0 : 1)
            .background { glow }
            .background {
                if let burstStart {
                    GamePetalBloom(start: burstStart, seed: seed)
                        .frame(width: 320, height: 240)
                }
            }
            .overlay { DailyChatRevealSparkles(trigger: landCount) }
            .task(id: isActive) { await play() }
    }

    private var glow: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color.paeoniaInkGold)
            .blur(radius: 18)
            .keyframeAnimator(initialValue: 0.0, trigger: landCount) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                CubicKeyframe(0.55, duration: 0.18)
                CubicKeyframe(0, duration: 1.1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func play() async {
        guard isActive else {
            isHidden = false
            return
        }
        guard !reduceMotion else {
            isHidden = false
            PaeoniaHaptics.partnerAnswerLanded()
            return
        }
        isHidden = true
        for intensity in [0.35, 0.65] {
            PaeoniaHaptics.revealBuildUp(intensity: intensity)
            try? await Task.sleep(for: Self.buildUpStep)
            guard !Task.isCancelled else { return }
        }
        withAnimation(.spring(duration: 0.55, bounce: 0.38)) {
            isHidden = false
        }
        burstStart = .now
        landCount += 1
        PaeoniaHaptics.partnerAnswerLanded()
    }
}

/// Gold sparkles that pop around a bubble's edge, one after another, each time `trigger`
/// changes. Positions are fractions of the bubble, so most sit just outside it.
private struct DailyChatRevealSparkles: View {
    private struct Spot {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let delay: TimeInterval
    }

    private static let spots: [Spot] = [
        Spot(x: -0.05, y: 0.15, size: 18, delay: 0),
        Spot(x: 0.22, y: -0.22, size: 12, delay: 0.06),
        Spot(x: 0.62, y: -0.26, size: 20, delay: 0.1),
        Spot(x: 1.06, y: 0.05, size: 14, delay: 0.04),
        Spot(x: 1.08, y: 0.78, size: 22, delay: 0.14),
        Spot(x: 0.7, y: 1.22, size: 12, delay: 0.08),
        Spot(x: 0.28, y: 1.2, size: 16, delay: 0.18),
        Spot(x: -0.07, y: 0.9, size: 11, delay: 0.12)
    ]

    let trigger: Int

    var body: some View {
        GeometryReader { proxy in
            ForEach(Self.spots.indices, id: \.self) { index in
                let spot = Self.spots[index]
                Image(systemName: "sparkle")
                    .font(.system(size: spot.size, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 3) ? Color.paeoniaTextPrimary : .paeoniaInkGold)
                    .shadow(color: .paeoniaInkGold.opacity(0.6), radius: 4)
                    .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, value in
                        view
                            .scaleEffect(value)
                            .rotationEffect(.degrees(value * 45))
                            .opacity(min(value * 2, 1))
                    } keyframes: { _ in
                        LinearKeyframe(0, duration: spot.delay)
                        SpringKeyframe(1.15, duration: 0.28, spring: .bouncy)
                        CubicKeyframe(0, duration: 0.5)
                    }
                    .position(x: spot.x * proxy.size.width, y: spot.y * proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
