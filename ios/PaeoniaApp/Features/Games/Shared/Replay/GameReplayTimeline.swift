import PencilKit
import UIKit

/// A finished drawing played back stroke by stroke at the pace it was drawn.
/// Strokes play in the order they were started. A pause between strokes never
/// lasts longer than `maxPause`. Times here are replay seconds from 0 to
/// `duration`, not drawing time.
///
/// The pixel eraser splits a stroke into pieces. Every piece keeps the whole
/// path, with the same `creationDate` and time offsets, and hides what was
/// erased with a mask. `PKStroke.maskedPathRanges` tells which part of the path
/// each piece still shows. A piece plays only that part, so erased ink costs no
/// time, and the pieces of one stroke play in the order they were drawn.
nonisolated struct GameReplayTimeline: Sendable {
    static let maxPause: TimeInterval = 1

    struct Item: Sendable {
        let stroke: PKStroke
        /// Replay time when the stroke's visible part starts being drawn.
        let start: TimeInterval
        /// Replay time when it is fully drawn.
        let end: TimeInterval
        /// The stroke's own time offset that goes with `start`.
        fileprivate let windowOffset: TimeInterval
    }

    let items: [Item]
    let duration: TimeInterval
    /// Tells timelines apart, so a surface knows when to start over. A scaled
    /// copy keeps it.
    let id: UUID

    /// A stroke on the original time line, in seconds. Only the part PencilKit
    /// still shows counts.
    private struct Timed {
        var stroke: PKStroke
        var windowOffset: TimeInterval
        var length: TimeInterval
        var start: TimeInterval
        var end: TimeInterval { start + length }
    }

    init(drawing: PKDrawing, maxPause: TimeInterval = Self.maxPause) {
        let timed = Self.onOriginalTimeLine(drawing)
        let origin = timed.first?.start ?? 0
        var latestEnd = origin
        var removedPause: TimeInterval = 0
        var items: [Item] = []
        for entry in timed {
            let pause = entry.start - latestEnd
            if pause > maxPause {
                removedPause += pause - maxPause
            }
            let start = entry.start - origin - removedPause
            items.append(Item(
                stroke: entry.stroke,
                start: start,
                end: start + entry.length,
                windowOffset: entry.windowOffset
            ))
            latestEnd = max(latestEnd, entry.end)
        }
        self.items = items
        duration = items.map(\.end).max() ?? 0
        id = UUID()
    }

    private init(items: [Item], duration: TimeInterval, id: UUID) {
        self.items = items
        self.duration = duration
        self.id = id
    }

    /// The same timeline for a canvas of `side` points, from the canonical size.
    func fitted(toSide side: CGFloat) -> GameReplayTimeline {
        let scaled = GameCanvas.fitted(PKDrawing(strokes: items.map(\.stroke)), toSide: side).strokes
        guard scaled.count == items.count else {
            return self
        }
        let fittedItems = zip(items, scaled).map { item, stroke in
            Item(stroke: stroke, start: item.start, end: item.end, windowOffset: item.windowOffset)
        }
        return GameReplayTimeline(items: fittedItems, duration: duration, id: id)
    }

    /// What `drawing(at:)` holds, split for a surface that draws the finished
    /// strokes only when one more finishes.
    struct Progress {
        /// How many strokes are done. Time only moves forward between restarts,
        /// so this count names the same strokes every time it repeats.
        var finishedCount: Int
        /// The strokes being drawn, cut at the points drawn so far, with their
        /// positions in `items`.
        var partials: [(index: Int, stroke: PKStroke)]
    }

    func progress(at time: TimeInterval) -> Progress {
        var finishedCount = 0
        var partials: [(index: Int, stroke: PKStroke)] = []
        for (index, item) in items.enumerated() where time >= item.start {
            if time >= item.end {
                finishedCount += 1
            } else if let stroke = Self.partialStroke(item, at: time) {
                partials.append((index, stroke))
            }
        }
        return Progress(finishedCount: finishedCount, partials: partials)
    }

    /// The strokes that are done at `time`.
    func finishedStrokes(at time: TimeInterval) -> [PKStroke] {
        items.filter { time >= $0.end }.map(\.stroke)
    }

    /// The drawing as the guesser sees it at `time`: strokes that have finished,
    /// plus the stroke in progress cut at the points drawn so far.
    func drawing(at time: TimeInterval) -> PKDrawing {
        PKDrawing(strokes: items.compactMap { item in
            if time < item.start {
                nil
            } else if time >= item.end {
                item.stroke
            } else {
                Self.partialStroke(item, at: time)
            }
        })
    }

    private static func onOriginalTimeLine(_ drawing: PKDrawing) -> [Timed] {
        drawing.strokes.enumerated()
            .compactMap { index, stroke in visibleWindow(of: stroke).map { (index, stroke, $0) } }
            .sorted { lhs, rhs in
                let (left, right) = (lhs.1.path.creationDate, rhs.1.path.creationDate)
                if left != right {
                    return left < right
                }
                return lhs.2.lowerBound != rhs.2.lowerBound ? lhs.2.lowerBound < rhs.2.lowerBound : lhs.0 < rhs.0
            }
            .map { _, stroke, window in
                Timed(
                    stroke: stroke,
                    windowOffset: window.lowerBound,
                    length: window.upperBound - window.lowerBound,
                    start: stroke.path.creationDate.timeIntervalSinceReferenceDate + window.lowerBound
                )
            }
    }

    /// The time offsets between which the stroke's visible part is drawn. Nil
    /// for a stroke without points.
    private static func visibleWindow(of stroke: PKStroke) -> ClosedRange<TimeInterval>? {
        let path = stroke.path
        guard let first = path.first, let last = path.last else {
            return nil
        }
        let ranges = stroke.maskedPathRanges
        guard let lower = ranges.map(\.lowerBound).min(), let upper = ranges.map(\.upperBound).max() else {
            return first.timeOffset...max(first.timeOffset, last.timeOffset)
        }
        let start = timeOffset(in: path, at: lower)
        return start...max(start, timeOffset(in: path, at: upper))
    }

    /// The time offset at a parametric position, between two control points.
    private static func timeOffset(in path: PKStrokePath, at parameter: CGFloat) -> TimeInterval {
        let position = min(max(parameter, 0), CGFloat(path.count - 1))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, path.count - 1)
        let fraction = TimeInterval(position - CGFloat(lower))
        return path[lower].timeOffset + (path[upper].timeOffset - path[lower].timeOffset) * fraction
    }

    private static func partialStroke(_ item: Item, at time: TimeInterval) -> PKStroke? {
        let path = item.stroke.path
        let elapsed = item.windowOffset + (time - item.start)
        let points = Array(path).prefix { $0.timeOffset <= elapsed }
        guard !points.isEmpty else {
            return nil
        }
        return PKStroke(
            ink: item.stroke.ink,
            path: PKStrokePath(controlPoints: Array(points), creationDate: path.creationDate),
            transform: item.stroke.transform,
            mask: item.stroke.mask,
            randomSeed: item.stroke.randomSeed
        )
    }
}
