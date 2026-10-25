import UIKit

/// Watches the touches on a canvas without taking part in them. Exquisite
/// Corpse uses it to show the partner where the pen is.
final class WidgetLiveTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onBegan: ((UITouch, UIEvent) -> Void)?
    var onMoved: ((UITouch, UIEvent) -> Void)?
    /// `true` when the system cancelled the touch.
    var onEnded: ((_ cancelled: Bool) -> Void)?

    private weak var trackedTouch: UITouch?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else {
            return
        }
        trackedTouch = touch
        onBegan?(touch, event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else {
            return
        }
        onMoved?(trackedTouch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, cancelled: true)
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let trackedTouch, touches.contains(trackedTouch) else {
            return
        }
        self.trackedTouch = nil
        onEnded?(cancelled)
        // Never recognizes, so it never takes the touches from the canvas.
        state = .failed
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
