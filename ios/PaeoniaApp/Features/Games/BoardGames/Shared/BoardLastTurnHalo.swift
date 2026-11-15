import SwiftUI

extension View {
    /// Shows this view as the soft halo that marks a piece of the partner's
    /// latest turn. It fades in `landing` seconds after it appears, once the
    /// piece under it has landed. It never takes touches, and VoiceOver skips it
    /// because the board's own description names the last move.
    ///
    /// It fades out when it is removed, so the board that holds the halos sets
    /// `.animation(BoardLastTurnHalo.fadeOut(reduceMotion:), value:)` on the set of marked moves.
    func boardLastTurnHalo(afterLanding landing: TimeInterval) -> some View {
        modifier(BoardLastTurnHalo(landing: landing))
    }
}

struct BoardLastTurnHalo: ViewModifier {
    let landing: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    /// The animation for a halo leaving the board, slow enough to notice that
    /// the turn moved on. Reduce Motion makes it a short fade.
    static func fadeOut(reduceMotion: Bool) -> Animation {
        PaeoniaMotion.standardCurve(duration: reduceMotion ? PaeoniaMotion.motionFast : PaeoniaMotion.motionSlow)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
            .onAppear {
                let fadeIn = reduceMotion
                    ? PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)
                    : PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow).delay(landing)
                withAnimation(fadeIn) { isShown = true }
            }
    }
}
