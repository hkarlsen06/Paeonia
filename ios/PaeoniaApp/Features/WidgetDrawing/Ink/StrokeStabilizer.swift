import CoreGraphics

/// Smooths a stroke as it is drawn, like a pen pulled behind the finger on a
/// short string. The pen moves only when the finger gets farther away than
/// the string's length, and then straight toward it. Wobble smaller than the
/// string never reaches the line, and the pen trails the finger by the
/// string's length at any speed. Pure: fed finger points, returns pen points.
nonisolated struct StrokeStabilizer: Sendable {
    /// In canvas points. Long enough to take out a finger's tremor and
    /// jitter, short enough that the line keeps up with a fast stroke.
    private static let stringLength: CGFloat = 1.5

    private var pen: CGPoint

    init(start: CGPoint) {
        pen = start
    }

    mutating func follow(_ finger: CGPoint) -> CGPoint {
        let distance = hypot(finger.x - pen.x, finger.y - pen.y)
        if distance > Self.stringLength {
            let pull = (distance - Self.stringLength) / distance
            pen.x += (finger.x - pen.x) * pull
            pen.y += (finger.y - pen.y) * pull
        }
        return pen
    }
}
