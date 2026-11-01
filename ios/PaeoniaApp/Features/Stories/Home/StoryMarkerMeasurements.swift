import SwiftUI

/// Space occupied around the portrait's center, including its note, frame and action.
nonisolated struct StoryMarkerMeasurements: Equatable, Sendable {
    var above: CGFloat = 0
    var below: CGFloat = 0
    var halfWidth: CGFloat = 0

    init() {}

    init(size: CGSize, noteHeight: CGFloat, portraitDiameter: CGFloat) {
        // A marker has no measured size before its first layout pass.
        guard size.height > 0 else { return }
        above = noteHeight + portraitDiameter / 2
        below = size.height - above
        halfWidth = size.width / 2
    }

    mutating func include(_ other: Self) {
        above = max(above, other.above)
        below = max(below, other.below)
        halfWidth = max(halfWidth, other.halfWidth)
    }
}
