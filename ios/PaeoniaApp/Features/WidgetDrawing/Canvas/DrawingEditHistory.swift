import PencilKit
import UIKit

/// Undo and redo for a drawing canvas. Each step keeps only the strokes it
/// added, changed, or removed, so undoing one of this person's steps leaves the
/// partner's strokes that arrived later where they are.
///
/// PencilKit's own undo stack is not used. It is lost each time the canvas gets
/// a drawing from code (a load, a resize, the partner's strokes), and it
/// remembers whole drawings, so an undo could wipe the partner's strokes.
nonisolated struct DrawingEditHistory {
    static let maxSteps = 100

    /// A stroke and its layer, so an undo puts it back under the ones above it.
    private struct LayeredStroke {
        var index: Int
        var stroke: PKStroke
        var signature = 0
    }

    /// The strokes a step replaced and the strokes it put in.
    private struct Step {
        var before: [LayeredStroke]
        var after: [LayeredStroke]
    }

    private var undoSteps: [Step] = []
    private var redoSteps: [Step] = []

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }

    /// The person changed `old` into `new`. Nothing is kept when no stroke changed.
    mutating func record(from old: PKDrawing, to new: PKDrawing) {
        let oldStrokes = Self.indexedByKey(old)
        let newStrokes = Self.indexedByKey(new)
        let before = oldStrokes.filter { key, entry in newStrokes[key]?.signature != entry.signature }
        let after = newStrokes.filter { key, entry in oldStrokes[key]?.signature != entry.signature }
        guard !before.isEmpty || !after.isEmpty else {
            return
        }
        undoSteps.append(Step(
            before: before.values.sorted { $0.index < $1.index },
            after: after.values.sorted { $0.index < $1.index }
        ))
        if undoSteps.count > Self.maxSteps {
            undoSteps.removeFirst()
        }
        redoSteps = []
    }

    /// `drawing` with the newest step taken back, or nil when there is none.
    mutating func undo(_ drawing: PKDrawing) -> PKDrawing? {
        guard let step = undoSteps.popLast() else {
            return nil
        }
        redoSteps.append(step)
        return Self.replace(step.after, with: step.before, in: drawing)
    }

    /// `drawing` with the last undone step done again, or nil when there is none.
    mutating func redo(_ drawing: PKDrawing) -> PKDrawing? {
        guard let step = redoSteps.popLast() else {
            return nil
        }
        undoSteps.append(step)
        return Self.replace(step.before, with: step.after, in: drawing)
    }

    /// The canvas shows another drawing now, so the steps no longer apply.
    mutating func removeAll() {
        undoSteps = []
        redoSteps = []
    }

    /// The canvas was resized and its drawing scaled. The kept strokes scale
    /// with it. A stroke's key survives scaling, so the steps still match.
    mutating func scale(fromSide oldSide: CGFloat, toSide newSide: CGFloat) {
        func scaled(_ entries: [LayeredStroke]) -> [LayeredStroke] {
            let strokes = PKDrawing(strokes: entries.map(\.stroke)).scaled(fromSide: oldSide, toSide: newSide).strokes
            return zip(entries, strokes).map { LayeredStroke(index: $0.index, stroke: $1) }
        }
        undoSteps = undoSteps.map { Step(before: scaled($0.before), after: scaled($0.after)) }
        redoSteps = redoSteps.map { Step(before: scaled($0.before), after: scaled($0.after)) }
    }

    private static func indexedByKey(_ drawing: PKDrawing) -> [String: LayeredStroke] {
        var result: [String: LayeredStroke] = [:]
        for (index, stroke) in drawing.strokes.enumerated() {
            result[WidgetLiveStrokeSync.key(for: stroke)] = LayeredStroke(
                index: index,
                stroke: stroke,
                signature: WidgetLiveStrokeSync.signature(for: stroke)
            )
        }
        return result
    }

    /// Takes `removed` out of `drawing` and puts `inserted` back at their layers.
    private static func replace(
        _ removed: [LayeredStroke],
        with inserted: [LayeredStroke],
        in drawing: PKDrawing
    ) -> PKDrawing {
        let removedKeys = Set((removed + inserted).map { WidgetLiveStrokeSync.key(for: $0.stroke) })
        var strokes = drawing.strokes.filter { !removedKeys.contains(WidgetLiveStrokeSync.key(for: $0)) }
        for entry in inserted {
            strokes.insert(entry.stroke, at: min(entry.index, strokes.count))
        }
        return PKDrawing(strokes: strokes)
    }
}
