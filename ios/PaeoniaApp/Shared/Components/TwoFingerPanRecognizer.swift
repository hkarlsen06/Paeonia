import UIKit.UIGestureRecognizerSubclass

/// How two fingers sit: how far apart, in points, and the angle of the line between them.
struct TwoFingers {
    let spread: CGFloat
    let angle: CGFloat

    /// How far the line between the fingers has turned since `earlier`, clockwise on
    /// screen. The line has no direction, so the turn is under a quarter turn either way,
    /// and the two fingers swapping places does not count.
    func twist(since earlier: Self) -> CGFloat {
        var twist = (angle - earlier.angle).truncatingRemainder(dividingBy: .pi)
        if twist > .pi / 2 { twist -= .pi }
        if twist < -.pi / 2 { twist += .pi }
        return twist
    }
}

/// A pan that also starts when two fingers spread, close or twist with their midpoint
/// still, which a plain pan never notices.
class TwoFingerPanRecognizer: UIPanGestureRecognizer {
    private static let pinchStart: CGFloat = 10
    /// How far two fingers twist before they count as turning, so a pinch does not turn.
    static let turnStart: CGFloat = 0.15
    /// Where two fingers were as they went down.
    private(set) var firstFingers: TwoFingers?

    /// Nil for one finger.
    var fingers: TwoFingers? {
        guard numberOfTouches == 2 else { return nil }
        let first = location(ofTouch: 0, in: view)
        let second = location(ofTouch: 1, in: view)
        return TwoFingers(
            spread: hypot(first.x - second.x, first.y - second.y),
            angle: atan2(second.y - first.y, second.x - first.x)
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if state == .possible, firstFingers == nil { firstFingers = fingers }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let fingers else { return }
        guard let firstFingers else {
            firstFingers = fingers
            return
        }
        if abs(fingers.spread - firstFingers.spread) > Self.pinchStart
            || abs(fingers.twist(since: firstFingers)) > Self.turnStart {
            state = .began
        }
    }

    override func reset() {
        super.reset()
        firstFingers = nil
    }
}
