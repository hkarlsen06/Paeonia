import CryptoKit
import PencilKit
import UIKit

/// The server's limits for one drawing (`backend/convex/widget.ts`). A drawing
/// past them can never be sent, so it is stopped before saving instead of
/// waiting forever on this phone and blocking the partner's next drawing.
nonisolated enum WidgetDrawingLimits {
    static let maxPayloadBytes = 2_097_152
    static let maxStrokes = 5_000
    static let maxPoints = 200_000

    static func allows(byteCount: Int, strokeCount: Int, pointCount: Int) -> Bool {
        byteCount <= maxPayloadBytes && strokeCount <= maxStrokes && pointCount <= maxPoints
    }
}

extension PKDrawing {
    /// A stable signature of just the visible strokes, so add-then-undo returns
    /// to the same value and a re-encode after saving does not. Built from each
    /// stroke's geometry and ink instead of `dataRepresentation()`, because the
    /// bytes also encode session state and PencilKit re-encodes them after every
    /// commit, so identical content would stop comparing equal right after a save.
    var paeoniaContentSignature: Int {
        var hasher = Hasher()
        hasher.combine(strokes.count)
        for stroke in strokes {
            hasher.combine(stroke.path.count)
            hasher.combine(stroke.ink.inkType)

            // Round to whole points so sub-pixel re-rendering noise after a
            // commit never reads as a change.
            let bounds = stroke.renderBounds
            hasher.combine(Int(bounds.minX.rounded()))
            hasher.combine(Int(bounds.minY.rounded()))
            hasher.combine(Int(bounds.width.rounded()))
            hasher.combine(Int(bounds.height.rounded()))

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            hasher.combine(Int((red * 255).rounded()))
            hasher.combine(Int((green * 255).rounded()))
            hasher.combine(Int((blue * 255).rounded()))
            hasher.combine(Int((alpha * 255).rounded()))
        }
        return hasher.finalize()
    }

    /// Names this set of strokes in a way that survives encoding, scaling, and
    /// app restarts, unlike `paeoniaContentSignature`, whose hash is seeded per
    /// launch.
    nonisolated var paeoniaStrokeFingerprint: String {
        let keys = strokes.map(WidgetLiveStrokeSync.key(for:)).sorted().joined(separator: ",")
        return SHA256.hash(data: Data(keys.utf8)).paeoniaHexString
    }

    var paeoniaPointCount: Int {
        strokes.reduce(0) { $0 + $1.path.count }
    }

    /// The same drawing on a canvas of `newSide` points. Strokes are stored in
    /// the coordinates of the square canvas they were drawn on, and that square
    /// differs between phones, so a drawing from a bigger screen would otherwise
    /// be cut off at the right and bottom edges.
    nonisolated func scaled(fromSide oldSide: CGFloat, toSide newSide: CGFloat) -> PKDrawing {
        guard oldSide > 0, newSide > 0, abs(oldSide - newSide) >= 0.5 else {
            return self
        }
        let factor = newSide / oldSide
        return transformed(using: CGAffineTransform(scaleX: factor, y: factor))
    }
}
