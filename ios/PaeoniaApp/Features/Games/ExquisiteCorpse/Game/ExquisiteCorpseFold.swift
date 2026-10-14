import PencilKit
import UIKit

/// Where one part of a figure folds, and how a drawing is cut at the fold.
/// The next drawer sees only the bottom `stripFraction` of the part before.
/// Everything is in the part's own coordinates, a square of `side` points
/// (`GameCanvas.canonicalSide` for stored parts).
nonisolated enum ExquisiteCorpseFold {
    /// The share of a part's height the next drawer sees.
    static let stripFraction: CGFloat = 0.12

    /// The y where the fold lies. The strip is everything at or below it.
    static func foldY(side: CGFloat = GameCanvas.canonicalSide) -> CGFloat {
        side * (1 - stripFraction)
    }

    /// The strip's area of the part.
    static func stripRect(side: CGFloat = GameCanvas.canonicalSide) -> CGRect {
        CGRect(x: 0, y: foldY(side: side), width: side, height: side * stripFraction)
    }

    /// The part clipped to the strip: only ink at or below the fold is left.
    ///
    /// - A stroke that lies above the fold is dropped.
    /// - A stroke that lies below it is kept as it is.
    /// - A stroke that crosses the fold keeps what lies below it. Each run
    ///   below the fold becomes its own stroke and starts or ends with a point
    ///   exactly on the fold line where the stroke crosses it.
    /// - Ink and transform stay. A masked stroke keeps only the runs that
    ///   `PKStroke.maskedPathRanges` still shows, so erased ink is gone, and its
    ///   mask is cut to the strip, because a mask is the outline of the whole
    ///   stroke and would carry its shape above the fold.
    /// - A paint bucket fill (`DrawingFloodFill`) is a wide line through the middle
    ///   of the filled area, with the area as its mask. It is drawn again over the
    ///   part of the area inside the strip, so neither the area nor the line above
    ///   the fold leaves the phone.
    ///
    /// A stroke is clipped by its curve, so a thick line just above the fold can
    /// still reach below it. The view clips what it draws to `stripRect`.
    static func strip(of drawing: PKDrawing, side: CGFloat = GameCanvas.canonicalSide) -> PKDrawing {
        let fold = foldY(side: side)
        let rect = stripRect(side: side)
        return PKDrawing(strokes: drawing.strokes.flatMap { stroke -> [PKStroke] in
            if isFill(stroke) {
                return fill(stroke, croppedTo: rect).map { [$0] } ?? []
            }
            return clipped(stroke, below: fold).compactMap { cropMask(of: $0, to: rect) }
        })
    }

    // MARK: Masks

    /// A paint bucket fill: two points whose width covers the whole masked area.
    /// A stroke the eraser cut has a mask too, but it is never wider than its mask.
    private static func isFill(_ stroke: PKStroke) -> Bool {
        guard let mask = stroke.mask, stroke.path.count <= 2, let first = stroke.path.first else {
            return false
        }
        return first.size.width > max(mask.bounds.width, mask.bounds.height)
    }

    /// The fill over the part of its area inside `rect`, built the way
    /// `DrawingFloodFill` builds one. Nil when none of the area is inside.
    private static func fill(_ stroke: PKStroke, croppedTo rect: CGRect) -> PKStroke? {
        guard let mask = stroke.mask else { return nil }
        let area = mask.cgPath.copy(using: [stroke.transform]) ?? mask.cgPath
        let inside = area.intersection(CGPath(rect: rect, transform: nil))
        let bounds = inside.boundingBoxOfPath
        guard !inside.isEmpty, bounds.width > 0, bounds.height > 0, let template = stroke.path.first else {
            return nil
        }
        let width = max(bounds.width, bounds.height) + 2
        let points = [bounds.minX, bounds.maxX].map { x in
            PKStrokePoint(
                location: CGPoint(x: x, y: bounds.midY),
                timeOffset: 0,
                size: CGSize(width: width, height: width),
                opacity: template.opacity,
                force: template.force,
                azimuth: template.azimuth,
                altitude: template.altitude
            )
        }
        return PKStroke(
            ink: stroke.ink,
            path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
            transform: .identity,
            mask: UIBezierPath(cgPath: inside),
            randomSeed: stroke.randomSeed
        )
    }

    /// The stroke with its mask cut to `rect`, which is in drawing coordinates.
    /// A stroke without a mask comes back as it is. Nil when nothing of the mask
    /// is inside.
    private static func cropMask(of stroke: PKStroke, to rect: CGRect) -> PKStroke? {
        guard let mask = stroke.mask else { return stroke }
        // The mask is in the stroke's own space, before its transform.
        let local = CGPath(rect: rect, transform: [stroke.transform.inverted()])
        let inside = mask.cgPath.intersection(local)
        guard !inside.isEmpty, !inside.boundingBoxOfPath.isEmpty else { return nil }
        var cropped = stroke
        cropped.mask = UIBezierPath(cgPath: inside)
        return cropped
    }

    // MARK: Clipping

    /// How far along the path (in control point steps) the fold search looks
    /// between two checks. A stroke that dips across the fold and back inside
    /// one step is not seen. A step is a few points long.
    private static let searchStep: CGFloat = 0.25

    /// A run shorter than this is a stroke that only touches the fold.
    private static let shortestRun: CGFloat = 1e-6

    private static func clipped(_ stroke: PKStroke, below fold: CGFloat) -> [PKStroke] {
        let path = stroke.path
        guard !path.isEmpty else {
            return []
        }
        // A B-spline stays inside the hull of its control points. All of them
        // above the fold means none of the stroke is below it, and all of them
        // below means all of it is, without looking at the curve.
        let controlYs = (0..<path.count).map { path[$0].location.applying(stroke.transform).y }
        if controlYs.allSatisfy({ $0 < fold }) {
            return []
        }
        let isBelow = controlYs.allSatisfy { $0 >= fold }
        if isBelow, stroke.mask == nil {
            return [stroke]
        }
        // A masked stroke is cut down to what it still shows, also below the
        // fold, so erased ink does not travel in the strip file.
        let last = CGFloat(path.count - 1)
        let shown = stroke.mask == nil ? [0...last] : stroke.maskedPathRanges
        let below = isBelow ? [0...last] : runsBelow(fold, in: stroke)
        var pieces: [ClosedRange<CGFloat>] = []
        for visible in shown {
            for run in below {
                let lower = max(visible.lowerBound, run.lowerBound)
                let upper = min(visible.upperBound, run.upperBound)
                if upper - lower > shortestRun {
                    pieces.append(lower...upper)
                }
            }
        }
        return pieces.sorted { $0.lowerBound < $1.lowerBound }.map { piece(of: stroke, in: $0, fold: fold) }
    }

    /// The parts of the path, as positions along it, where the curve is at or
    /// below the fold. Their ends are found to well under a thousandth of a point.
    private static func runsBelow(_ fold: CGFloat, in stroke: PKStroke) -> [ClosedRange<CGFloat>] {
        let path = stroke.path
        let last = CGFloat(path.count - 1)
        func isBelow(_ position: CGFloat) -> Bool {
            path.interpolatedLocation(at: position).applying(stroke.transform).y >= fold
        }
        var runs: [ClosedRange<CGFloat>] = []
        var start: CGFloat? = isBelow(0) ? 0 : nil
        var position: CGFloat = 0
        while position < last {
            let next = min(position + searchStep, last)
            let wasBelow = start != nil
            if isBelow(next) != wasBelow {
                let boundary = Self.crossing(between: position, and: next, isBelow: isBelow)
                if let begun = start {
                    runs.append(begun...boundary)
                    start = nil
                } else {
                    start = boundary
                }
            }
            position = next
        }
        if let start {
            runs.append(start...last)
        }
        return runs
    }

    /// The position between `from` and `to` where `isBelow` flips, as the side
    /// of it that is below the fold.
    private static func crossing(
        between from: CGFloat,
        and to: CGFloat,
        isBelow: (CGFloat) -> Bool
    ) -> CGFloat {
        var (low, high) = (from, to)
        let lowIsBelow = isBelow(low)
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if isBelow(middle) == lowIsBelow {
                low = middle
            } else {
                high = middle
            }
        }
        return lowIsBelow ? low : high
    }

    /// The stroke between two positions along its path: a point on the curve at
    /// each end and the control points between them. The new path is a spline
    /// of its own, so next to a cut it can differ from the old curve by far
    /// less than a point.
    private static func piece(of stroke: PKStroke, in range: ClosedRange<CGFloat>, fold: CGFloat) -> PKStroke {
        let path = stroke.path
        let last = CGFloat(path.count - 1)
        // The ends of a path are control points. Anywhere else the curve only
        // passes near them, so a point on the curve stands in.
        func point(at position: CGFloat) -> PKStrokePoint {
            if position <= 0 { return path[0] }
            if position >= last { return path[path.count - 1] }
            return path.interpolatedPoint(at: position)
        }
        let firstInside = Int(range.lowerBound.rounded(.down)) + 1
        let endInside = max(firstInside, Int(range.upperBound.rounded(.up)))
        var points = [point(at: range.lowerBound)]
        points += (firstInside..<endInside).map { path[$0] }
        points.append(point(at: range.upperBound))
        // The curve only passes near its control points, so one can lie above the
        // fold while the curve is below it. Such a point moves onto the fold line:
        // a spline stays inside the hull of its control points, so nothing of the
        // piece, neither its curve nor its stored points, is above the fold.
        let inverse = stroke.transform.inverted()
        points = points.map { point in
            let placed = point.location.applying(stroke.transform)
            guard placed.y < fold else { return point }
            return PKStrokePoint(
                location: CGPoint(x: placed.x, y: fold).applying(inverse),
                timeOffset: point.timeOffset,
                size: point.size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold
            )
        }
        return PKStroke(
            ink: stroke.ink,
            path: PKStrokePath(controlPoints: points, creationDate: path.creationDate),
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
        )
    }
}
