import SwiftUI

extension View {
    /// A steady ring means only that the partner has this game open.
    /// Callers supply spoken presence separately from game progress.
    func gamePresenceRing(_ isHere: Bool) -> some View {
        overlay { GamePresenceRing(isHere: isHere) }
    }
}

private struct GamePresenceRing: View {
    let isHere: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrivalCount = 0

    var body: some View {
        let suppressMotion = reduceMotion || !isHere
        Circle()
            .strokeBorder(.paeoniaSuccess, lineWidth: PaeoniaRadius.strokeEmphasis)
            .padding(-4)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: arrivalCount) { ring, scale in
                ring.scaleEffect(suppressMotion ? 1 : scale)
            } keyframes: { _ in
                CubicKeyframe(1.12, duration: PaeoniaMotion.motionFast)
                CubicKeyframe(1, duration: PaeoniaMotion.motionSlow)
            }
            .animation(nil) { $0.opacity(isHere ? 1 : 0) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: isHere) { wasHere, isHere in
                if !wasHere, isHere, !reduceMotion { arrivalCount += 1 }
            }
    }
}
