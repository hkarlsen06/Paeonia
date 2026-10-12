import SwiftUI

/// A letter on a rounded square. It is the same view in the tile grid and in an
/// answer slot, so a tile can fly from one to the other.
struct DrawAndGuessTileFace: View {
    let letter: Character
    var fill: Color = .paeoniaSurfacePrimary
    var textColor: Color = .paeoniaTextPrimary

    var body: some View {
        Text(String(letter))
            .font(PaeoniaTypography.title)
            .foregroundStyle(textColor)
            // The grid keeps six columns, so the letters stop growing at this size.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
    }
}

/// Lets a tile fly between the grid and a slot. Reduce Motion turns the flight
/// off, and the tile cross-fades instead.
struct DrawAndGuessTileFlight: ViewModifier {
    let id: Int
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.opacity)
        } else {
            content.matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

/// Moves its content from side to side once for each change of `trigger`: three
/// swings of 8 points over `motionSlow`.
struct DrawAndGuessShake: ViewModifier {
    let trigger: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: isEnabled ? offset : 0)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(8, duration: 0.03)
                LinearKeyframe(-8, duration: 0.06)
                LinearKeyframe(8, duration: 0.06)
                LinearKeyframe(-8, duration: 0.06)
                LinearKeyframe(8, duration: 0.06)
                LinearKeyframe(-8, duration: 0.06)
                LinearKeyframe(0, duration: 0.03)
            }
        }
    }
}
