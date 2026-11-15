import SwiftUI

/// One finger or two move the bubble by their midpoint, and two make the video bigger or smaller as
/// they spread or close when it `zooms`. Reports, in window points, how far the midpoint has moved
/// and how much the spread has grown since the fingers went down.
struct CallBubbleGesture: UIGestureRecognizerRepresentable {
    let zooms: Bool
    let changed: (_ translation: CGSize, _ scale: CGFloat) -> Void
    let ended: (_ translation: CGSize, _ scale: CGFloat, _ velocity: CGSize) -> Void
    let cancelled: () -> Void

    final class Grip {
        var translation = CGSize.zero
        var scale: CGFloat = 1
        var point = CGPoint.zero
        var fingers: TwoFingers?
        /// A pinch ends with the fingers lifting one by one, which must not fling or tuck the bubble.
        var hadTwoFingers = false

        /// A finger landing or lifting moves the midpoint without moving the bubble.
        func step(to point: CGPoint, fingers: TwoFingers?, zooms: Bool) {
            if (fingers == nil) == (self.fingers == nil) {
                translation.width += point.x - self.point.x
                translation.height += point.y - self.point.y
                if zooms, let fingers, let last = self.fingers { scale *= fingers.spread / max(last.spread, 1) }
            }
            self.point = point
            self.fingers = fingers
            if fingers != nil { hadTwoFingers = true }
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Grip {
        Grip()
    }

    func makeUIGestureRecognizer(context: Context) -> TwoFingerPanRecognizer {
        let pan = TwoFingerPanRecognizer()
        pan.maximumNumberOfTouches = 2
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: TwoFingerPanRecognizer, context: Context) {
        let grip = context.coordinator
        let point = pan.location(in: nil)
        switch pan.state {
        case .began:
            // The first step catches up from where the fingers went down.
            let fingers = pan.firstFingers ?? pan.fingers
            grip.translation = .zero
            grip.scale = 1
            grip.point = pan.startLocation ?? point
            grip.fingers = fingers
            grip.hadTwoFingers = fingers != nil
            grip.step(to: point, fingers: pan.fingers, zooms: zooms)
            changed(grip.translation, grip.scale)
        case .changed:
            grip.step(to: point, fingers: pan.fingers, zooms: zooms)
            changed(grip.translation, grip.scale)
        case .ended:
            let velocity = grip.hadTwoFingers ? .zero : pan.velocity(in: nil)
            ended(grip.translation, grip.scale, CGSize(width: velocity.x, height: velocity.y))
        case .cancelled, .failed:
            cancelled()
        default:
            break
        }
    }
}
