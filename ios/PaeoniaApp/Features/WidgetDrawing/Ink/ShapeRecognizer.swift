import CoreGraphics
import Foundation

/// Decides which clean shape, if any, a rough stroke was drawn as.
nonisolated enum ShapeRecognizer {
    nonisolated struct Tuning: Sendable {
        /// Points the stroke is respaced to. Enough to follow a heart's notch,
        /// and it beat 48 and 96 on recall at the same false snaps.
        var sampleCount = 64
        /// Touches closer than this to the last kept one are jitter, mostly
        /// from the finger held still at the end.
        var jitter: CGFloat = 3
        /// Strokes with smaller bounds are taps and dots.
        var minimumSize: CGFloat = 20
        /// A stroke is closed when its ends are nearer than this share of its
        /// length. Hand-drawn shapes leave gaps up to about 15 percent.
        var closedGap: CGFloat = 0.2
        /// The last share of a stroke searched for where it passes its start
        /// again, so an overshoot of up to 40 percent is trimmed off.
        var overshootSearch: CGFloat = 0.3
        /// Angles this close to level or upright become exact. A finger rarely
        /// draws a level side, and a nearly level one was meant to be.
        var axisSnap: CGFloat = 6 * .pi / 180
        /// A turn this sharp over a short stretch is a corner, which no
        /// ellipse has. Leaves, eyes, clouds and hexagons fit an ellipse
        /// closely otherwise.
        var cornerTurn: CGFloat = 45 * .pi / 180
        /// The short turn must also be this share of the turn over twice the
        /// stretch. The end of a thin ellipse turns as sharply but keeps turning.
        var cornerShare: CGFloat = 0.75
        /// The short stretch spans at least this many points, so touch jitter
        /// on a small shape does not read as a corner.
        var cornerReach: CGFloat = 10
        /// One corner alone rules out an ellipse only when it turns this
        /// sharply. A finger drawing a small circle kinks it by about 50 degrees.
        var sharpCornerTurn: CGFloat = 60 * .pi / 180
        /// An ellipse whose short radius is at least this share of its long
        /// one becomes a circle. Circles drawn with a finger come out at 0.85
        /// to 0.95, and ovals at 0.69 to 0.74.
        var circleRatio: CGFloat = 0.82
        /// A heart tilted further than this is some other closed shape.
        var heartTilt: CGFloat = 30 * .pi / 180
        /// A heart's height over its width. Hearts drawn with a finger come
        /// out at 0.88 to 1.23, and a flatter fit is a D or a letter e.
        var heartAspect: ClosedRange<CGFloat> = 0.7...1.5
        /// How far from a heart's notch toward its tip the stroke may run
        /// inside the heart without counting against the fit.
        var notchStem: CGFloat = 0.3
        /// How far, in heart heights, the stroke must dip at a heart's notch.
        /// Circles, gems and octagons fit a heart closely but have no notch.
        var notchDip: CGFloat = 0.01
        /// Residual added per row down the candidate table, so a near tie goes
        /// to the simpler shape.
        var simplerShapeMargin: CGFloat = 0.0015
        /// The highest residual each shape accepts. Each is about the loosest
        /// value that kept false snaps on scribbles, letters and arcs under
        /// 0.4 percent on a synthetic corpus of rough strokes.
        var lineLimit: CGFloat = 0.033
        var ellipseLimit: CGFloat = 0.024
        var rectangleLimit: CGFloat = 0.024
        /// Looser, because a rounded sharp corner leaves the fitted corner well
        /// outside the stroke.
        var triangleLimit: CGFloat = 0.031
        var heartLimit: CGFloat = 0.030

        static let standard = Tuning()
    }

    /// One candidate shape fitted to a stroke.
    nonisolated struct Fit: Sendable {
        var kind: SnappedShape.Kind
        /// How far the stroke and the outline lie apart, over the stroke's
        /// bounding diagonal. From the stroke to the outline it is the root
        /// mean square distance, so a piece of stroke off the outline (the bar
        /// of an e, the inner turn of a spiral) costs a lot. From the outline
        /// to the stroke it is the plain mean, so a side the stroke never drew
        /// costs, but the short gap people leave when closing a shape does
        /// not. The larger of the two counts.
        var residual: CGFloat
        var isAccepted: Bool
        var score: CGFloat
    }

    /// The shape `points` look like, or nil. The outline starts at the outline
    /// point nearest `points[0]` and runs the way the stroke was drawn.
    static func recognize(_ points: [CGPoint], tuning: Tuning = .standard) -> SnappedShape? {
        guard let stroke = Stroke(points, tuning: tuning) else {
            return nil
        }
        let best = stroke.fits(tuning).filter(\.isAccepted).min { $0.score < $1.score }
        return best.map { stroke.oriented($0.kind) }
    }
}

nonisolated private extension ShapeRecognizer {
    /// One row per shape. A new shape is one more row.
    struct Candidate: Sendable {
        var isClosed: Bool
        var limit: @Sendable (Tuning) -> CGFloat
        var fit: @Sendable (Stroke, Tuning) -> SnappedShape.Kind?
    }

    /// Simplest first, because a near tie goes to the earlier row.
    static let candidates: [Candidate] = [
        Candidate(isClosed: false, limit: { $0.lineLimit }, fit: fitLine),
        Candidate(isClosed: true, limit: { $0.ellipseLimit }, fit: fitEllipse),
        Candidate(isClosed: true, limit: { $0.rectangleLimit }, fit: fitRectangle),
        Candidate(isClosed: true, limit: { $0.triangleLimit }, fit: fitTriangle),
        Candidate(isClosed: true, limit: { $0.heartLimit }, fit: fitHeart),
    ]
}

nonisolated extension ShapeRecognizer {
    /// The rough stroke respaced evenly, with any overshoot past its start
    /// trimmed off.
    struct Stroke {
        let points: [CGPoint]
        let isClosed: Bool
        let diagonal: CGFloat

        init?(_ touches: [CGPoint], tuning: Tuning) {
            guard var last = touches.first else {
                return nil
            }
            var kept = [last]
            for touch in touches.dropFirst() where touch.distance(to: last) >= tuning.jitter {
                kept.append(touch)
                last = touch
            }
            guard kept.count >= 2, boundingDiagonal(kept) >= tuning.minimumSize else {
                return nil
            }
            let closing = Self.closing(kept, tuning: tuning)
            isClosed = closing.isClosed
            points = Polyline.resampled(Array(kept[...closing.end]), count: tuning.sampleCount)
            diagonal = boundingDiagonal(points)
        }

        /// Every candidate that fits, accepted or not. Turning a shape level or
        /// upright and rounding an ellipse to a circle tidy it after the stroke
        /// matched it, so they never count against the match.
        func fits(_ tuning: Tuning) -> [Fit] {
            var untidied = tuning
            untidied.axisSnap = 0
            untidied.circleRatio = .infinity
            return candidates.enumerated().compactMap { rank, candidate in
                guard candidate.isClosed == isClosed,
                      let kind = candidate.fit(self, tuning),
                      let matched = candidate.fit(self, untidied)
                else {
                    return nil
                }
                let residual = min(residual(of: kind, tuning), residual(of: matched, tuning))
                return Fit(
                    kind: kind,
                    residual: residual,
                    isAccepted: residual <= candidate.limit(tuning),
                    score: residual + CGFloat(rank) * tuning.simplerShapeMargin
                )
            }
        }

        func residual(of kind: SnappedShape.Kind, _ tuning: Tuning) -> CGFloat {
            let contour = kind.contour
            let count = CGFloat(points.count)
            // Fingers start and end a heart in its notch and often pull down
            // into it, so stroke along a line from the notch toward the tip
            // counts as on the outline.
            var stem: (from: CGPoint, to: CGPoint)?
            if case .heart = kind {
                let notch = contour.points[0]
                stem = (notch, notch.interpolated(to: contour.points[contour.points.count / 2], by: tuning.notchStem))
            }
            let toOutline = points.reduce(0) { sum, point in
                let onOutline = distance(from: point, to: contour.points, isClosed: contour.isClosed)
                let onStem = stem.map { sqrt(segmentDistanceSquared(point, $0.from, $0.to)) } ?? .infinity
                return sum + pow(min(onOutline, onStem), 2)
            }
            let samples = Polyline.resampled(contour.points, count: points.count, isClosed: contour.isClosed)
            let toStroke = samples.reduce(0) { $0 + distance(from: $1, to: points, isClosed: false) }
            return max(sqrt(toOutline / count), toStroke / count) / diagonal
        }

        func oriented(_ kind: SnappedShape.Kind) -> SnappedShape {
            let contour = kind.contour
            let first = points[0]
            guard contour.isClosed else {
                let fromEnd = first.distance(to: contour.points[contour.points.count - 1])
                return SnappedShape(kind: kind, start: 0, isReversed: fromEnd < first.distance(to: contour.points[0]))
            }
            let start = nearestFraction(of: first, aroundLoop: contour.points)
            let isReversed = (signedArea(points) < 0) != (signedArea(contour.points) < 0)
            return SnappedShape(kind: kind, start: start, isReversed: isReversed)
        }

        /// Where the stroke comes back nearest its start, searched near its
        /// end, and whether that is near enough to call the stroke closed.
        /// An open stroke keeps all of its points.
        private static func closing(_ points: [CGPoint], tuning: Tuning) -> (end: Int, isClosed: Bool) {
            var lengths: [CGFloat] = [0]
            lengths.reserveCapacity(points.count)
            for index in points.indices.dropFirst() {
                lengths.append(lengths[index - 1] + points[index - 1].distance(to: points[index]))
            }
            let searchFrom = (1 - tuning.overshootSearch) * lengths[lengths.count - 1]
            var end = points.count - 1
            for index in points.indices where lengths[index] >= searchFrom
                && points[index].distance(to: points[0]) < points[end].distance(to: points[0]) {
                end = index
            }
            let isClosed = points[end].distance(to: points[0]) < tuning.closedGap * lengths[end]
            return isClosed ? (end, true) : (points.count - 1, false)
        }
    }
}

nonisolated extension ShapeRecognizer {
    static func axisSnapped(_ angle: CGFloat, _ tuning: Tuning) -> CGFloat {
        let axis = (angle / (.pi / 2)).rounded() * (.pi / 2)
        return abs(angle - axis) <= tuning.axisSnap ? axis : angle
    }

    static func mean(_ points: [CGPoint]) -> CGPoint {
        points.reduce(.zero) { $0 + $1 } * (1 / CGFloat(points.count))
    }

    static func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    static func boundingDiagonal(_ points: [CGPoint]) -> CGFloat {
        let box = bounds(points)
        return hypot(box.width, box.height)
    }

    static func signedArea(_ points: [CGPoint]) -> CGFloat {
        points.indices.reduce(0) { $0 + points[$1].cross(points[($1 + 1) % points.count]) } / 2
    }

    static func segmentDistanceSquared(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let edge = end - start
        let lengthSquared = edge.dot(edge)
        let along = lengthSquared > 0 ? max(0, min(1, (point - start).dot(edge) / lengthSquared)) : 0
        let gap = point - (start + edge * along)
        return gap.dot(gap)
    }
}

nonisolated private extension ShapeRecognizer {
    static func distance(from point: CGPoint, to polyline: [CGPoint], isClosed: Bool) -> CGFloat {
        let segmentCount = isClosed ? polyline.count : polyline.count - 1
        var nearest = CGFloat.infinity
        for index in 0..<segmentCount {
            let end = polyline[(index + 1) % polyline.count]
            nearest = min(nearest, segmentDistanceSquared(point, polyline[index], end))
        }
        return sqrt(nearest)
    }

    /// How far around the closed `loop` its point nearest `point` is, as a
    /// fraction of the loop's length.
    static func nearestFraction(of point: CGPoint, aroundLoop loop: [CGPoint]) -> CGFloat {
        var travelled: CGFloat = 0
        var nearest = (distance: CGFloat.infinity, position: CGFloat(0))
        for index in loop.indices {
            let start = loop[index]
            let edge = loop[(index + 1) % loop.count] - start
            let length = hypot(edge.x, edge.y)
            let along = length > 0 ? max(0, min(1, (point - start).dot(edge) / (length * length))) : 0
            let distance = point.distance(to: start + edge * along)
            if distance < nearest.distance {
                nearest = (distance, travelled + along * length)
            }
            travelled += length
        }
        return travelled > 0 ? nearest.position / travelled : 0
    }
}

/// Point arithmetic for the shape geometry, kept to this file.
fileprivate nonisolated extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    func dot(_ other: CGPoint) -> CGFloat {
        x * other.x + y * other.y
    }

    func cross(_ other: CGPoint) -> CGFloat {
        x * other.y - y * other.x
    }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func interpolated(to other: CGPoint, by fraction: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
    }
}
