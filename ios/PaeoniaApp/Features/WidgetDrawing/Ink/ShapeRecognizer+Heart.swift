import CoreGraphics
import Foundation

/// How the heart in the candidate table fits itself to a stroke.
nonisolated extension ShapeRecognizer {
    /// The heart, among proportions from a shallow to a deep notch, that lies
    /// closest to the stroke, leaned to follow where the stroke put its tip.
    static func fitHeart(_ stroke: Stroke, _ tuning: Tuning) -> SnappedShape.Kind? {
        let best = heartStarts
            .compactMap { fitHeart(stroke, start: $0, tuning) }
            .min { stroke.residual(of: $0, tuning) < stroke.residual(of: $1, tuning) }
        guard let best, (notchDip(of: stroke.points, under: best) ?? .infinity) >= tuning.notchDip else {
            return nil
        }
        return best
    }

    /// How far the top edge of the stroke dips near the heart's notch, below
    /// the lower of its highest points either side, in heart heights. Nil
    /// when the stroke leaves its closing gap over the notch, as a heart
    /// started and ended there can. The edge is measured in columns 0.02
    /// heart widths wide, and the notch spans 0.12 widths either side.
    private static func notchDip(of points: [CGPoint], under kind: SnappedShape.Kind) -> CGFloat? {
        guard case let .heart(center, size, rotation, shape) = kind, let first = points.first, let last = points.last
        else {
            return nil
        }
        let columnWidth: CGFloat = 0.02
        let notchColumns = -6...6
        let upperPart = shape.template[0].y + 0.25
        func upright(_ point: CGPoint) -> (column: Int, depth: CGFloat) {
            let turned = (point - center).rotated(by: -rotation)
            let depth = turned.y / size.height
            return (Int(((turned.x / size.width - shape.lean * depth) / columnWidth).rounded()), depth)
        }
        let ends = [upright(first), upright(last)]
        let gap = ends.map(\.column).sorted()
        if gap[1] - gap[0] > 2, (gap[0]...gap[1]).overlaps(notchColumns), ends.allSatisfy({ $0.depth < upperPart }) {
            return nil
        }
        var topEdge: [Int: CGFloat] = [:]
        for point in Polyline.resampled(points, count: 4 * points.count, isClosed: true) {
            let (column, depth) = upright(point)
            if depth < upperPart {
                topEdge[column] = min(topEdge[column] ?? .infinity, depth)
            }
        }
        guard let atNotch = topEdge.filter({ notchColumns.contains($0.key) }).values.max(),
              let left = topEdge.filter({ $0.key < notchColumns.lowerBound }).values.min(),
              let right = topEdge.filter({ $0.key > notchColumns.upperBound }).values.min()
        else {
            return 0
        }
        return atNotch - max(left, right)
    }

    /// Proportions the heart fit starts from: lobes that meet just below the
    /// top or almost as low as their centers, and short to long sides.
    private static let heartStarts = [CGFloat(0.71), 0.99].flatMap { spread in
        [CGFloat(2.1), 2.9, 3.8].map { SnappedShape.HeartShape(spread: spread, tipDepth: $0) }
    }

    /// Fits the heart by pairing each stroke point with its nearest template
    /// point and solving for the affine map between them, a few times over,
    /// so the heart can run wide or tall, turn, and put its tip off center.
    /// A heart turned nearly level is then refitted level.
    private static func fitHeart(
        _ stroke: Stroke,
        start shape: SnappedShape.HeartShape,
        _ tuning: Tuning
    ) -> SnappedShape.Kind? {
        let template = shape.template
        guard let placement = HeartPlacement(stroke.points, template: template, tuning: tuning) else {
            return nil
        }
        var map = HeartMap(angle: placement.angle, scale: placement.scale, offset: placement.offset)
        let pairing = HeartPairing(template: template, notchStem: tuning.notchStem)
        for _ in 0..<3 {
            guard let refined = pairing.refined(map, toward: stroke.points) else {
                return nil
            }
            map = refined
        }
        let angle = atan2(map.across.y, map.across.x)
        guard abs(angle) <= tuning.heartTilt else {
            return nil
        }
        let level = axisSnapped(angle, tuning)
        if level != angle {
            guard let levelled = pairing.refined(map, toward: stroke.points, turn: level) else {
                return nil
            }
            map = levelled
        }
        return map.heart(shape, tuning)
    }

    /// Least squares for `target = slopes.x * x + slopes.y * y + intercept`
    /// over the `source` points.
    static func planeFit(_ source: [CGPoint], _ target: [CGFloat]) -> (slopes: CGPoint, intercept: CGFloat)? {
        var matrix = [[Double]](repeating: [0, 0, 0], count: 3)
        var sums: [Double] = [0, 0, 0]
        for (point, value) in zip(source, target) {
            let terms = [Double(point.x), Double(point.y), 1]
            for row in 0..<3 {
                sums[row] += terms[row] * Double(value)
                for column in 0..<3 {
                    matrix[row][column] += terms[row] * terms[column]
                }
            }
        }
        guard let solution = solve(matrix, sums) else {
            return nil
        }
        return (CGPoint(x: solution[0], y: solution[1]), solution[2])
    }
}

/// Pairs stroke points with the template and refits the map to them. Stroke
/// pulled down into the notch, along a line from the notch toward the tip,
/// stays out of the fit.
nonisolated private struct HeartPairing {
    var template: [CGPoint]
    var notch: CGPoint
    var stemEnd: CGPoint

    init(template: [CGPoint], notchStem: CGFloat) {
        self.template = template
        notch = template[0]
        stemEnd = notch.interpolated(to: template[template.count / 2], by: notchStem)
    }

    /// The map that best carries the paired template points onto the stroke.
    /// With a `turn`, the map keeps that turn and fits only the size, lean
    /// and offset.
    func refined(_ map: HeartMap, toward points: [CGPoint], turn: CGFloat? = nil) -> HeartMap? {
        var matches: [CGPoint] = []
        var matched: [CGPoint] = []
        for point in points {
            let unit = map.unit(of: point)
            let match = template[ShapeRecognizer.nearestIndex(to: unit, in: template)]
            let gap = unit - match
            if ShapeRecognizer.segmentDistanceSquared(unit, notch, stemEnd) >= gap.dot(gap) {
                matches.append(match)
                matched.append(point)
            }
        }
        guard matched.count >= points.count / 2 else {
            return nil
        }
        guard let turn else {
            guard let fitX = ShapeRecognizer.planeFit(matches, matched.map(\.x)),
                  let fitY = ShapeRecognizer.planeFit(matches, matched.map(\.y))
            else {
                return nil
            }
            return HeartMap(
                across: CGPoint(x: fitX.slopes.x, y: fitY.slopes.x),
                down: CGPoint(x: fitX.slopes.y, y: fitY.slopes.y),
                offset: CGPoint(x: fitX.intercept, y: fitY.intercept)
            )
        }
        let local = matched.map { $0.rotated(by: -turn) }
        guard let fitX = ShapeRecognizer.planeFit(matches, local.map(\.x)),
              let fitY = ShapeRecognizer.lineFit(matches.map(\.y), local.map(\.y))
        else {
            return nil
        }
        return HeartMap(
            across: CGPoint(x: fitX.slopes.x, y: 0).rotated(by: turn),
            down: CGPoint(x: fitX.slopes.y, y: fitY.slope).rotated(by: turn),
            offset: CGPoint(x: fitX.intercept, y: fitY.intercept).rotated(by: turn)
        )
    }
}

/// An affine map from the unit heart template onto the canvas: the images
/// of the template's across and down axes, and of its origin.
nonisolated private struct HeartMap {
    var across: CGPoint
    var down: CGPoint
    var offset: CGPoint

    init(across: CGPoint, down: CGPoint, offset: CGPoint) {
        self.across = across
        self.down = down
        self.offset = offset
    }

    init(angle: CGFloat, scale: CGFloat, offset: CGPoint) {
        across = CGPoint(x: cos(angle), y: sin(angle)) * scale
        down = CGPoint(x: -sin(angle), y: cos(angle)) * scale
        self.offset = offset
    }

    /// Where `point` sits in template coordinates.
    func unit(of point: CGPoint) -> CGPoint {
        let determinant = across.cross(down)
        let gap = point - offset
        return CGPoint(x: gap.cross(down) / determinant, y: across.cross(gap) / determinant)
    }

    /// The map as a turn, a width and height, and a lean of the down axis.
    /// Nil when it mirrors the heart, leans it too far, or squashes it.
    func heart(_ shape: SnappedShape.HeartShape, _ tuning: ShapeRecognizer.Tuning) -> SnappedShape.Kind? {
        let width = hypot(across.x, across.y)
        let angle = atan2(across.y, across.x)
        let upright = down.rotated(by: -angle)
        guard width > 0, upright.y > 0, tuning.heartAspect.contains(upright.y / width) else {
            return nil
        }
        var fitted = shape
        fitted.lean = upright.x / width
        guard fitted.isValid else {
            return nil
        }
        return .heart(center: offset, size: CGSize(width: width, height: upright.y), rotation: angle, shape: fitted)
    }
}

/// The best near-upright rotation, scale and offset of the heart template onto
/// a stroke, pairing them point for point from every start and in both
/// directions, since people start a heart at the notch, the tip, or anywhere.
/// This is Umeyama's similarity fit in the plane.
nonisolated private struct HeartPlacement {
    var angle: CGFloat
    var scale: CGFloat
    var offset: CGPoint

    init?(_ points: [CGPoint], template: [CGPoint], tuning: ShapeRecognizer.Tuning) {
        let count = points.count
        let anchors = Polyline.resampled(template, count: count, isClosed: true)
        let anchorMean = ShapeRecognizer.mean(anchors)
        let pointMean = ShapeRecognizer.mean(points)
        let centeredAnchors = anchors.map { $0 - anchorMean }
        let centeredPoints = points.map { $0 - pointMean }
        var best: (dot: CGFloat, cross: CGFloat)?
        for ordered in [centeredPoints, centeredPoints.reversed()] {
            for shift in 0..<count {
                var dot: CGFloat = 0
                var cross: CGFloat = 0
                for index in 0..<count {
                    let anchor = centeredAnchors[(index + shift) % count]
                    dot += anchor.dot(ordered[index])
                    cross += anchor.cross(ordered[index])
                }
                let isStronger = hypot(dot, cross) > (best.map { hypot($0.dot, $0.cross) } ?? 0)
                if isStronger, abs(atan2(cross, dot)) <= tuning.heartTilt {
                    best = (dot, cross)
                }
            }
        }
        guard let best else {
            return nil
        }
        angle = atan2(best.cross, best.dot)
        scale = hypot(best.dot, best.cross) / centeredAnchors.reduce(0) { $0 + $1.dot($1) }
        offset = pointMean - (anchorMean * scale).rotated(by: angle)
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

    func interpolated(to other: CGPoint, by fraction: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
    }

    func rotated(by angle: CGFloat) -> CGPoint {
        CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }
}
