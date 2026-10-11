import PencilKit

/// The partner's canvas as seen from the Home tab while they draw. It starts
/// from the snapshot they send and follows their changes.
nonisolated struct WidgetLiveRoom {
    /// Strokes are kept in this canvas size and scaled for display.
    static let side: CGFloat = 320

    private(set) var drawing: PKDrawing?
    /// Changes whenever `drawing` does, so the view knows to redraw.
    private(set) var version = 0
    private var scaledCache: ScaledStrokes?

    private struct ScaledStrokes {
        let version: Int
        let side: CGFloat
        let strokes: [PKStroke]
    }

    /// `upserts` must already be scaled to `Self.side`.
    mutating func apply(_ message: WidgetLiveMessage, upserts: [PKStroke]) {
        if message.snapshot == true {
            drawing = PKDrawing(strokes: upserts)
        } else {
            drawing = WidgetLiveStrokeSync.apply(
                upserts: upserts,
                removals: message.removals ?? [],
                to: drawing ?? PKDrawing()
            )
        }
        version += 1
    }

    mutating func clear() {
        guard drawing != nil else {
            return
        }
        drawing = nil
        version += 1
    }

    /// The strokes for a view of `side` points. Cached, because the view asks
    /// on every frame.
    mutating func strokes(side: CGFloat) -> [PKStroke] {
        guard let drawing else {
            return []
        }
        if let scaledCache, scaledCache.version == version, scaledCache.side == side {
            return scaledCache.strokes
        }
        let strokes = drawing.scaled(fromSide: Self.side, toSide: side).strokes
        scaledCache = ScaledStrokes(version: version, side: side, strokes: strokes)
        return strokes
    }
}
