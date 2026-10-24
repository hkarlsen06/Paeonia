import SwiftUI

// Coordination between the cold-launch intro (`LaunchExperienceView`, mounted in
// `RootView`) and the first app surface it uncovers. The intro exits by opening a
// circular hole through its canvas while the surface's content cascades in. These are
// the cues the content reads to animate itself in.

private struct LaunchContentRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

private struct LaunchSidesUncoveredKey: EnvironmentKey {
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

    /// Flips true when the intro's opening hole reaches the screen's left and right
    /// edges. The Home map's flame sweep starts here, so it plays as the screen opens
    /// rather than behind the overlay. Defaults to true outside the cold launch.
    var launchSidesUncovered: Bool {
        get { self[LaunchSidesUncoveredKey.self] }
        set { self[LaunchSidesUncoveredKey.self] = newValue }
    }

    /// True once the cold-launch intro has fully finished. Launch-adjacent moments
    /// that shouldn't compete with the intro (e.g. streak celebrations) can wait on
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

    /// The same lifted drop-in cascade as `launchEntrance(order:)`, but cued by the
    /// screen's own first appearance — for screens the user reaches mid-session, like
    /// the profile setup screen right after signing in. During a cold launch it still
    /// waits for the intro's content cue, so both paths feel identical. A screen
    /// whose content is still loading can hold the drop with `isReady`. Once true,
    /// it must stay true.
    func screenEntrance(order: Int, isReady: Bool = true) -> some View {
        modifier(ScreenEntranceModifier(order: order, isReady: isReady))
    }
}

/// Shared feel of the entrance cascade, so launch-cued and appearance-cued screens
/// drop their content in identically.
private enum EntranceCascade {
    /// How far above its resting place each element starts before dropping in.
    static let rise: CGFloat = 26
    /// Gap between each element's entrance, so the cascade flows down the screen.
    static let stagger: TimeInterval = 0.08

    static func entrance(order: Int, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else {
            // No positional motion under Reduce Motion — just a gentle fade in.
            return .easeOut(duration: PaeoniaMotion.motionDefault)
        }

        return .spring(response: 0.5, dampingFraction: 0.68)
            .delay(Double(order) * stagger)
    }
}

private struct LaunchEntranceModifier: ViewModifier {
    let order: Int

    @Environment(\.launchContentRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Moves the subtree as one, so views inserted mid-drop (like plan prices
            // arriving from the App Store) drop with it instead of appearing at the end spot.
            .geometryGroup()
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : -EntranceCascade.rise)
            .animation(EntranceCascade.entrance(order: order, reduceMotion: reduceMotion), value: revealed)
    }
}

private struct ScreenEntranceModifier: ViewModifier {
    let order: Int
    let isReady: Bool

    @Environment(\.launchContentRevealed) private var launchRevealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLaidOut = false

    /// During a cold launch the intro's cue gates the drop-in; mid-session the first
    /// layout with a real size does, so the cascade plays right as the screen arrives.
    /// A new screen's first layout pass can have zero width. Dropping in during that
    /// pass would animate the content and its place on screen from the empty size.
    private var revealed: Bool {
        isLaidOut && launchRevealed && isReady
    }

    func body(content: Content) -> some View {
        content
            // Moves the subtree as one, so views inserted mid-drop (like plan prices
            // arriving from the App Store) drop with it instead of appearing at the end spot.
            .geometryGroup()
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : -EntranceCascade.rise)
            .animation(EntranceCascade.entrance(order: order, reduceMotion: reduceMotion), value: revealed)
            .onGeometryChange(for: Bool.self) { $0.size.width > 0 } action: { hasWidth in
                if hasWidth {
                    isLaidOut = true
                }
            }
    }
}
