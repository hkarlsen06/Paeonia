import SwiftUI

/// A straight line that draws from `start` toward `end`. `progress` runs from
/// 0 to 1 and animates, so the line trims in.
nonisolated struct UltimateTicTacToeStrikeShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.001, start != end else { return path }
        path.move(to: start)
        path.addLine(to: CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        ))
        return path
    }
}

/// A mark that draws in like ink: it grows from 60% with a circle that opens
/// from its middle and fades in over the same span.
struct UltimateTicTacToeInkReveal: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        let progress: CGFloat = phase.isIdentity ? 1 : 0
        content
            .scaleEffect(0.6 + 0.4 * progress)
            .mask { Circle().scale(0.04 + 1.5 * progress) }
            .opacity(progress)
    }
}

/// Pulses the view's scale once for each change of `trigger`.
struct UltimateTicTacToePulse: ViewModifier {
    let trigger: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
            view.scaleEffect(isEnabled ? scale : 1)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.1, duration: 0.15)
                SpringKeyframe(1.0, duration: 0.4)
            }
        }
    }
}
