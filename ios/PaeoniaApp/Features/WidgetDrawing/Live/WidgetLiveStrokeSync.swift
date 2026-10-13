import PencilKit
import UIKit

/// Keeps both canvases holding the same strokes. Each phone sends the strokes it
/// added, changed, or removed, and applies the partner's changes to its own
/// canvas. Adding strokes works in any order, so the two canvases end up the
/// same even when both people draw at once.
nonisolated enum WidgetLiveStrokeSync {
    /// `PKStroke` has no id. The path's creation time, point count, and random
    /// seed survive encoding and scaling, so together they name a stroke on both
    /// phones.
    static func key(for stroke: PKStroke) -> String {
        let milliseconds = Int64((stroke.path.creationDate.timeIntervalSinceReferenceDate * 1_000).rounded())
        return "\(milliseconds)-\(stroke.path.count)-\(stroke.randomSeed)"
    }

    /// Changes when the eraser, a move, or a color change touches the stroke.
    static func signature(for stroke: PKStroke) -> Int {
        var hasher = Hasher()
        hasher.combine(stroke.ink.inkType.rawValue)
        hasher.combine(stroke.ink.color)
        let transform = stroke.transform
        for value in [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty] {
            hasher.combine(value)
        }
        hasher.combine(stroke.mask?.cgPath)
        for range in stroke.maskedPathRanges {
            hasher.combine(range.lowerBound)
            hasher.combine(range.upperBound)
        }
        return hasher.finalize()
    }

    /// `drawing` with `removals` taken out and `upserts` put in. A stroke that is
    /// already there is replaced in place, so it keeps its layer.
    static func apply(upserts: [PKStroke], removals: [String], to drawing: PKDrawing) -> PKDrawing {
        let removed = Set(removals)
        var strokes = drawing.strokes.filter { !removed.contains(key(for: $0)) }
        var positions: [String: Int] = [:]
        for (position, stroke) in strokes.enumerated() {
            positions[key(for: stroke)] = position
        }
        for stroke in upserts {
            let strokeKey = key(for: stroke)
            if let position = positions[strokeKey] {
                strokes[position] = stroke
            } else {
                positions[strokeKey] = strokes.count
                strokes.append(stroke)
            }
        }
        return PKDrawing(strokes: strokes)
    }

    struct JoinResult {
        var drawing: PKDrawing
        /// Strokes drawn here while this screen was open that the partner does
        /// not have yet. They join the shared canvas.
        var ownUnsent: [PKStroke]
        /// The canvas held other unsent strokes, such as an old draft. They do
        /// not join the shared canvas. The caller sets the old canvas aside.
        var hasOtherUnsentStrokes: Bool
    }

    /// Joining a canvas someone already has open: take their strokes, and add
    /// the ones drawn here (`drawnHereKeys`) that they do not have.
    /// `roomRemovals` are strokes the partner removed. They had them, so they
    /// are not unsent strokes from here, and they stay removed.
    static func join(
        room: [PKStroke],
        local: PKDrawing,
        savedKeys: Set<String>,
        drawnHereKeys: Set<String>,
        roomRemovals: Set<String> = []
    ) -> JoinResult {
        let roomKeys = Set(room.map(key(for:)))
        let unsent = local.strokes.filter { stroke in
            let strokeKey = key(for: stroke)
            return !savedKeys.contains(strokeKey) && !roomKeys.contains(strokeKey) && !roomRemovals.contains(strokeKey)
        }
        let ownUnsent = unsent.filter { drawnHereKeys.contains(key(for: $0)) }
        return JoinResult(
            drawing: PKDrawing(strokes: room + ownUnsent),
            ownUnsent: ownUnsent,
            hasOtherUnsentStrokes: ownUnsent.count < unsent.count
        )
    }
}

/// Remembers the strokes the partner already has, so each change sends only
/// what is new.
nonisolated struct WidgetLiveStrokeTracker {
    struct Changes {
        var upserts: [PKStroke]
        var removals: [String]

        var isEmpty: Bool { upserts.isEmpty && removals.isEmpty }
    }

    private var signatures: [String: Int] = [:]

    /// The drawing changed without a person drawing (a load, a resize, or the
    /// partner's strokes). There is nothing to send for it.
    mutating func reset(to drawing: PKDrawing) {
        _ = changes(to: drawing)
    }

    /// The strokes added or changed since the last call, and the keys removed.
    mutating func changes(to drawing: PKDrawing) -> Changes {
        var next: [String: Int] = [:]
        var upserts: [PKStroke] = []
        for stroke in drawing.strokes {
            let key = WidgetLiveStrokeSync.key(for: stroke)
            let signature = WidgetLiveStrokeSync.signature(for: stroke)
            next[key] = signature
            if signatures[key] != signature {
                upserts.append(stroke)
            }
        }
        let removals = signatures.keys.filter { next[$0] == nil }.sorted()
        signatures = next
        return Changes(upserts: upserts, removals: removals)
    }
}
