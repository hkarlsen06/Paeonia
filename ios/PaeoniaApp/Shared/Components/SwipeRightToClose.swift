import SwiftUI
import UIKit

extension View {
    /// Runs `action` on a swipe right, the usual way to leave a page on iOS. The swipe
    /// needs the same distance or speed as the chat's back swipe. `isEnabled` should
    /// follow whether the page's own Close or Back button works.
    func closesOnSwipeRight(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        contentShape(.rect)
            .gesture(SwipeRightToCloseGesture(isEnabled: isEnabled, action: action))
    }
}

/// A pan that runs beside the page's other gestures, so buttons, fields and scrolling
/// keep working. The page does not follow the finger, because the cover animates its
/// own dismissal once the action closes it.
private struct SwipeRightToCloseGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> SwipeRightToCloseDelegate {
        SwipeRightToCloseDelegate()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context _: Context) {
        pan.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context _: Context) {
        guard pan.state == .ended else { return }
        let translation = pan.translation(in: pan.view)
        let velocity = pan.velocity(in: pan.view)
        guard ThreadChatPanGestureResolver.shouldTriggerNavigationBack(
            translation: CGSize(width: translation.x, height: translation.y),
            velocity: CGSize(width: velocity.x, height: velocity.y)
        ) else { return }
        action()
    }
}

private final class SwipeRightToCloseDelegate: NSObject, UIGestureRecognizerDelegate {
    /// A slider and a calendar's months move on a drag right, and so does the caret in a
    /// field being typed in. None of those should close the page.
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !touch.startsInView { view in
            view is UISlider || view is UIDatePicker || (view is UITextInput && view.isFirstResponder)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: pan.view)
        return ThreadChatPanGestureResolver.hasDirectionalHorizontalIntent(
            velocity: CGSize(width: velocity.x, height: velocity.y),
            direction: .right
        )
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension UITouch {
    /// Whether the view the touch went down on, or one of the views it sits in, matches.
    func startsInView(where matches: (UIView) -> Bool) -> Bool {
        guard let view else { return false }
        return sequence(first: view, next: \.superview).contains(where: matches)
    }
}
