import CoreGraphics
import Foundation

/// Notices when the finger has stayed still long enough. Pure: fed points and
/// times, asked for the deadline.
nonisolated struct HoldDetector: Sendable {
    /// Wider than a resting finger's jitter. Drawing slower than
    /// radius / duration (16 points a second) also reads as holding.
    var radius: CGFloat = 8
    var duration: TimeInterval = 0.5

    private var anchor: CGPoint?
    private var anchorTime: TimeInterval = 0
    private var isArmed = false

    /// Re-anchors, and re-arms, when `point` leaves `radius` around the anchor.
    mutating func add(_ point: CGPoint, at time: TimeInterval) {
        if let anchor, hypot(point.x - anchor.x, point.y - anchor.y) <= radius {
            return
        }
        anchor = point
        anchorTime = time
        isArmed = true
    }

    /// When the hold completes if the finger stays. Nil when disarmed or empty.
    var deadline: TimeInterval? {
        isArmed ? anchorTime + duration : nil
    }

    /// After a failed recognition: no deadline until the finger leaves the radius.
    mutating func disarmUntilMoved() {
        isArmed = false
    }
}
