import PencilKit
import UIKit

/// The strip of each stroke on the canvas, kept between sends. The strip goes
/// out up to 12 times a second while a stroke is drawn, and scaling and cutting
/// every stroke on each send grows with the drawing. A finished stroke only
/// needs it once, until the eraser or a move changes it.
nonisolated struct ExquisiteCorpseStripCache {
    private var side: CGFloat = 0
    private var entries: [String: [PKStroke]] = [:]

    /// The strip of a canvas of `side` points holding `strokes`, plus the stroke
    /// still being drawn. It is in the canonical size, like
    /// `ExquisiteCorpseFold.strip(of:)` of the whole drawing.
    mutating func strip(of strokes: [PKStroke], including liveStroke: PKStroke?, fromSide side: CGFloat) -> PKDrawing {
        if side != self.side {
            entries = [:]
            self.side = side
        }
        var kept: [String: [PKStroke]] = [:]
        var result: [PKStroke] = []
        for stroke in strokes {
            let key = "\(WidgetLiveStrokeSync.key(for: stroke))-\(WidgetLiveStrokeSync.signature(for: stroke))"
            let pieces = entries[key] ?? Self.strip(of: stroke, fromSide: side)
            kept[key] = pieces
            result += pieces
        }
        // Strokes that left the canvas, such as erased ones, leave the cache too.
        entries = kept
        if let liveStroke {
            result += Self.strip(of: liveStroke, fromSide: side)
        }
        return PKDrawing(strokes: result)
    }

    private static func strip(of stroke: PKStroke, fromSide side: CGFloat) -> [PKStroke] {
        ExquisiteCorpseFold.strip(of: GameCanvas.canonical(PKDrawing(strokes: [stroke]), fromSide: side)).strokes
    }
}
