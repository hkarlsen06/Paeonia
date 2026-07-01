import SwiftUI

// Coordination between the cold-launch intro (`LaunchExperienceView`, mounted in
// `RootView`) and the first app surface it uncovers. The intro exits by dropping its
// backdrop and drifting the logo away while the surface's content cascades in, rather
// than masking — so these are the cues the content reads to animate itself in.

private struct LaunchContentRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

private struct LaunchIntroCompleteKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Flips true when the cold-launch intro begins its exit, cueing the first app
    /// surface to animate its content in (see `View.launchEntrance(order:)`). Defaults
    /// to true so content outside the cold launch (tab switches, previews) shows at once.
    var launchContentRevealed: Bool {
        get { self[LaunchContentRevealedKey.self] }
        set { self[LaunchContentRevealedKey.self] = newValue }
    }

    /// True once the cold-launch intro has fully finished. Launch-adjacent reveals that
    /// shouldn't compete with the intro (e.g. the Home map's flame sweep) can wait on
    /// this. Defaults to true so anything outside the cold launch behaves normally.
    var launchIntroComplete: Bool {
        get { self[LaunchIntroCompleteKey.self] }
        set { self[LaunchIntroCompleteKey.self] = newValue }
    }
}

extension View {
    /// Animates this view in as part of the cold-launch reveal: it starts lifted and
    /// hidden, then drops into place with a soft bounce once the intro cues the content
    /// (`launchContentRevealed`). `order` staggers the cascade top-to-bottom (0 first),
    /// so the surface fills in from the top down. Outside the cold launch the content is
    /// simply shown, with no animation.
    func launchEntrance(order: Int) -> some View {
        modifier(LaunchEntranceModifier(order: order))
    }
}

private struct LaunchEntranceModifier: ViewModifier {
    let order: Int

    @Environment(\.launchContentRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far above its resting place each element starts before dropping in.
    private static let rise: CGFloat = 26
    /// Gap between each element's entrance, so the cascade flows down the screen.
    private static let stagger: TimeInterval = 0.08

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : -Self.rise)
            .animation(entrance, value: revealed)
    }

    private var entrance: Animation? {
        guard !reduceMotion else {
            // No positional motion under Reduce Motion — just a gentle fade in.
            return .easeOut(duration: PaeoniaMotion.motionDefault)
        }

        return .spring(response: 0.5, dampingFraction: 0.68)
            .delay(Double(order) * Self.stagger)
    }
}
