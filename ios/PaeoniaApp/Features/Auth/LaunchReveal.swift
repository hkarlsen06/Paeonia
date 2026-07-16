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

    /// The same lifted drop-in cascade as `launchEntrance(order:)`, but cued by the
    /// screen's own first appearance — for screens the user reaches mid-session, like
    /// the profile setup screen right after signing in. During a cold launch it still
    /// waits for the intro's content cue, so both paths feel identical.
    func screenEntrance(order: Int) -> some View {
        modifier(ScreenEntranceModifier(order: order))
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
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : -EntranceCascade.rise)
            .animation(EntranceCascade.entrance(order: order, reduceMotion: reduceMotion), value: revealed)
    }
}

private struct ScreenEntranceModifier: ViewModifier {
    let order: Int

    @Environment(\.launchContentRevealed) private var launchRevealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    /// During a cold launch the intro's cue gates the drop-in; mid-session the first
    /// rendered frame does, so the cascade plays right as the screen arrives.
    private var revealed: Bool {
        hasAppeared && launchRevealed
    }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : -EntranceCascade.rise)
            .animation(EntranceCascade.entrance(order: order, reduceMotion: reduceMotion), value: revealed)
            .task {
                hasAppeared = true
            }
    }
}
