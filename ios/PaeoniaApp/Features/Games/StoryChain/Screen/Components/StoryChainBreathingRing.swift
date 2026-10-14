import SwiftUI

/// A soft ring that breathes around an avatar while the partner is in the game.
/// It stays in the layout and fades in and out. The breathing animation covers
/// only the ring's opacity, so the ring moves with the avatar when the layout
/// changes. Reduce Motion shows a still ring.
struct StoryChainBreathingRing: View {
    let isActive: Bool
    var lineWidth: CGFloat = 4
    /// How far the ring sits outside the avatar.
    var inset: CGFloat = PaeoniaSpacing.space8
    var blur: CGFloat = 1.5
    var peak = 0.5
    var trough = 0.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        Circle()
            .stroke(.paeoniaAccentPrimary, lineWidth: lineWidth)
            .padding(-inset)
            .blur(radius: blur)
            .animation(reduceMotion ? nil : breathing) {
                $0.opacity(reduceMotion ? (peak + trough) / 2 : isBreathing ? peak : trough)
            }
            .opacity(isActive ? 1 : 0)
            .onAppear { isBreathing = true }
            .accessibilityHidden(true)
    }

    private var breathing: Animation {
        PaeoniaMotion.standardCurve(duration: 2.4).repeatForever(autoreverses: true)
    }
}
