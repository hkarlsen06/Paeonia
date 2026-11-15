import SwiftUI

extension View {
    /// A steady ring means only that the partner has this game open.
    /// Callers supply spoken presence separately from game progress.
    /// `outset` is how far outside the view the ring sits, so it can clear
    /// another ring, such as the board games' turn ring.
    func gamePresenceRing(_ isHere: Bool, outset: CGFloat = 4) -> some View {
        overlay { GamePresenceRing(isHere: isHere, outset: outset) }
    }
}

private struct GamePresenceRing: View {
    let isHere: Bool
    let outset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrivalCount = 0

    var body: some View {
        let suppressMotion = reduceMotion || !isHere
        Circle()
            .strokeBorder(.paeoniaPresence, lineWidth: PaeoniaRadius.strokeEmphasis)
            .padding(-outset)
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
