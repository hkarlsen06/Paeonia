import SwiftUI

/// How big the square is, so a phase never resizes it. The width decides, and the
/// height left after the rows around it keeps it on screen.
nonisolated enum GameMetrics {
    /// The square never grows past this, so strokes keep their weight.
    static let maxSquare: CGFloat = 640
    /// The widest the right column grows in the wide layout.
    static let sideColumnWidth: CGFloat = 420
    /// Height kept for the rows above and below the square on a phone, until the
    /// layout has measured them (`GamePhaseLayout`).
    static let reservedHeight: CGFloat = 340
    /// The square on a phone never shrinks below this. Smaller screens scroll.
    static let minSquare: CGFloat = 200
    /// Space above and below the scrolling rows.
    static let scrollPadding = PaeoniaSpacing.space8 + PaeoniaSpacing.space16
    static let wideMinWidth: CGFloat = 700

    static func isWide(_ size: CGSize) -> Bool {
        size.width >= wideMinWidth && size.width > size.height
    }

    /// - Parameter heightRatio: The square content's height divided by its side.
    ///   It is 1 for a plain square. A square with a strip above it is taller than wide.
    static func squareSide(in size: CGSize, heightRatio: CGFloat = 1) -> CGFloat {
        let padding = PaeoniaSpacing.screenHorizontalPadding * 2
        if isWide(size) {
            let beside = size.width - sideColumnWidth - PaeoniaSpacing.space32 - padding
            return max(200, min(maxSquare, beside, (size.height - PaeoniaSpacing.space24 * 2) / heightRatio))
        }
        let byHeight = max(220, (size.height - reservedHeight) / heightRatio)
        return max(minSquare, min(maxSquare, size.width - padding, byHeight))
    }

    /// The side that makes the rows and the square fill the height exactly.
    /// - Parameters:
    ///   - measuredSide: The side the rows were measured with.
    ///   - contentHeight: The height of the scrolling rows with that side.
    ///   - bottomHeight: The height of the pinned bottom cluster.
    ///   - heightRatio: The square content's height divided by its side. The slack
    ///     is the height of the square content, so a side grows by the slack divided by the ratio.
    static func fittedSide(
        in size: CGSize,
        measuredSide: CGFloat,
        contentHeight: CGFloat,
        bottomHeight: CGFloat,
        heightRatio: CGFloat = 1
    ) -> CGFloat {
        let slack = size.height - bottomHeight - contentHeight - scrollPadding
        let widthLimit = min(maxSquare, size.width - PaeoniaSpacing.screenHorizontalPadding * 2)
        // Whole points, so a measurement that lands a hair off does not move the square again.
        return max(minSquare, min(widthLimit, (measuredSide + slack / heightRatio).rounded(.down)))
    }
}

/// The square's side as the drawer's drawing screen settled it. The drawer's result
/// screen takes the same side, so the square does not change size when the
/// drawing is sent.
@MainActor
final class GameSideMemory {
    var side: CGFloat?
}
