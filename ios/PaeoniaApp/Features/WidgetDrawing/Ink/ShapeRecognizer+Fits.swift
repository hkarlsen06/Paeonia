import CoreGraphics
import Foundation

/// How each shape in the candidate table fits itself to a stroke.
nonisolated extension ShapeRecognizer {
    static func fitLine(_ stroke: Stroke, _ tuning: Tuning) -> SnappedShape.Kind? {
        let from = stroke.points[0]
        let to = stroke.points[stroke.points.count - 1]
        let halfLength = from.distance(to: to) / 2
        guard halfLength > 0 else {
            return nil
        }
        let angle = axisSnapped(atan2(to.y - from.y, to.x - from.x), tuning)
        let middle = from.interpolated(to: to, by: 0.5)
        let offset = CGPoint(x: cos(angle), y: sin(angle)) * halfLength
        return .line(from: middle - offset, to: middle + offset)
    }

    static func fitEllipse(_ stroke: Stroke, _ tuning: Tuning) -> SnappedShape.Kind? {
        // Leaves, eyes and hexagons sit close to an ellipse but turn sharply in places.
        guard !hasCorner(stroke.points, tuning), let conic = Conic(stroke.points, scale: stroke.diagonal) else {
            return nil
        }
        let angle = axisSnapped(atan2(conic.xy, conic.xx - conic.yy) / 2, tuning)
        let along = conic.xx * cos(angle) * cos(angle) + conic.xy * sin(angle) * cos(angle)
            + conic.yy * sin(angle) * sin(angle)
        let across = conic.xx * sin(angle) * sin(angle) - conic.xy * sin(angle) * cos(angle)
            + conic.yy * cos(angle) * cos(angle)
        guard conic.level > 0, along > 0, across > 0 else {
            return nil
        }
        let radii = CGSize(
            width: sqrt(conic.level / along) * stroke.diagonal,
            height: sqrt(conic.level / across) * stroke.diagonal
        )
        if min(radii.width, radii.height) >= tuning.circleRatio * max(radii.width, radii.height) {
            let radius = (radii.width + radii.height) / 2
            return .ellipse(center: conic.center, radii: CGSize(width: radius, height: radius), rotation: 0)
        }
        return .ellipse(center: conic.center, radii: radii, rotation: angle)
    }

    static func fitRectangle(_ stroke: Stroke, _ tuning: Tuning) -> SnappedShape.Kind? {
        let hull = convexHull(stroke.points)
        guard hull.count >= 3 else {
            return nil
        }
        // The smallest box around a convex shape has a side along one of its edges.
        let smallest = hull.indices.map { index in
            let edge = hull[(index + 1) % hull.count] - hull[index]
            let angle = atan2(edge.y, edge.x)
            let box = bounds(hull.map { $0.rotated(by: -angle) })
            return (angle: angle, area: box.width * box.height)
        }.min { $0.area < $1.area }
        let angle = axisSnapped(smallest?.angle ?? 0, tuning)
        let local = stroke.points.map { $0.rotated(by: -angle) }
        let box = bounds(local)
        // Each side moves to the median of the points nearest it, so wobble
        // and rounded corners do not push it outward.
        var sides: [[CGFloat]] = [[], [], [], []]
        for point in local {
            let gaps = [point.x - box.minX, box.maxX - point.x, point.y - box.minY, box.maxY - point.y]
            let side = gaps.indices.min { gaps[$0] < gaps[$1] } ?? 0
            sides[side].append(side < 2 ? point.x : point.y)
        }
        let minX = median(sides[0]) ?? box.minX
        let maxX = median(sides[1]) ?? box.maxX
        let minY = median(sides[2]) ?? box.minY
        let maxY = median(sides[3]) ?? box.maxY
        guard maxX > minX, maxY > minY else {
            return nil
        }
        let corners = [(minX, minY), (maxX, minY), (maxX, maxY), (minX, maxY)].map { CGPoint(x: $0.0, y: $0.1) }
        return .polygon(corners.map { $0.rotated(by: angle) })
    }

    static func fitTriangle(_ stroke: Stroke, _ tuning: Tuning) -> SnappedShape.Kind? {
        let hull = convexHull(stroke.points)
        guard hull.count >= 3 else {
            return nil
        }
        var corners = largestTriangle(in: hull)
        for _ in 0..<2 {
            guard let refined = refinedTriangle(corners, toward: stroke.points) else {
                break
            }
            corners = refined
        }
        return .polygon(levelled(corners, tuning))
    }
}

/// The ellipse that best fits points by least squares. Around `center` it is
/// xx·x² + xy·x·y + yy·y² = level, in coordinates divided by `scale` so the
/// system stays well conditioned for any stroke size. The fit itself solves
/// xx·x² + xy·x·y + yy·y² + dx·x + dy·y = 1 around the centroid.
nonisolated private struct Conic {
    var xx: CGFloat
    var xy: CGFloat
    var yy: CGFloat
    var level: CGFloat
    var center: CGPoint

    init?(_ points: [CGPoint], scale: CGFloat) {
        let centroid = ShapeRecognizer.mean(points)
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 5), count: 5)
        var sums = [Double](repeating: 0, count: 5)
        for point in points {
            let local = (point - centroid) * (1 / scale)
            let terms = [local.x * local.x, local.x * local.y, local.y * local.y, local.x, local.y].map(Double.init)
            for row in 0..<5 {
                sums[row] += terms[row]
                for column in 0..<5 {
                    matrix[row][column] += terms[row] * terms[column]
                }
            }
        }
        guard let coefficients = ShapeRecognizer.solve(matrix, sums) else {
            return nil
        }
        xx = coefficients[0]
        xy = coefficients[1]
        yy = coefficients[2]
        let (dx, dy) = (coefficients[3], coefficients[4])
        let determinant = 4 * xx * yy - xy * xy
        // Anything else is a parabola or a hyperbola.
        guard determinant > 0 else {
            return nil
        }
        let local = CGPoint(
            x: (xy * dy - 2 * yy * dx) / determinant,
            y: (xy * dx - 2 * xx * dy) / determinant
        )
        level = 1 + xx * local.x * local.x + xy * local.x * local.y + yy * local.y * local.y
        center = centroid + local * scale
    }
}

nonisolated private extension ShapeRecognizer {
    /// Whether the stroke turns sharply over a short stretch and then stops
    /// turning, in two places or once very sharply. The end of a thin ellipse
    /// turns as sharply, but keeps turning over a longer stretch. One milder
    /// kink is a finger slipping on a round shape.
    static func hasCorner(_ points: [CGPoint], _ tuning: Tuning) -> Bool {
        func turn(at index: Int, reach: Int) -> CGFloat {
            let before = points[index] - points[index - reach]
            let after = points[index + reach] - points[index]
            return abs(atan2(before.cross(after), before.dot(after)))
        }
        let spacing = points[0].distance(to: points[1])
        let reach = max(2, Int((tuning.cornerReach / max(spacing, 0.1)).rounded(.up)))
        let wideReach = 2 * reach
        guard points.count > 2 * wideReach else {
            return false
        }
        let corners = (wideReach..<(points.count - wideReach)).filter { index in
            let sharp = turn(at: index, reach: reach)
            return sharp >= tuning.cornerTurn && sharp >= tuning.cornerShare * turn(at: index, reach: wideReach)
        }
        guard let first = corners.first, let last = corners.last else {
            return false
        }
        return last - first > reach || corners.contains { turn(at: $0, reach: reach) >= tuning.sharpCornerTurn }
    }

    static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
    }

    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else {
            return sorted
        }
        func chain(_ points: [CGPoint]) -> [CGPoint] {
            var chain: [CGPoint] = []
            for point in points {
                while chain.count >= 2,
                      (chain[chain.count - 1] - chain[chain.count - 2]).cross(point - chain[chain.count - 2]) <= 0 {
                    chain.removeLast()
                }
                chain.append(point)
            }
            return chain.dropLast()
        }
        return chain(sorted) + chain(sorted.reversed())
    }

    /// The largest triangle with corners on a convex hull. For each first
    /// corner, the best third corner only moves forward as the second does.
    static func largestTriangle(in hull: [CGPoint]) -> [CGPoint] {
        func area(_ first: Int, _ second: Int, _ third: Int) -> CGFloat {
            abs((hull[second] - hull[first]).cross(hull[third] - hull[first]))
        }
        var best = [0, 1, 2]
        for first in 0..<(hull.count - 2) {
            var third = first + 2
            for second in (first + 1)..<(hull.count - 1) {
                third = max(third, second + 1)
                while third + 1 < hull.count, area(first, second, third + 1) >= area(first, second, third) {
                    third += 1
                }
                if area(first, second, third) > area(best[0], best[1], best[2]) {
                    best = [first, second, third]
                }
            }
        }
        return best.map { hull[$0] }
    }

    /// The triangle whose sides are the lines that best fit the stroke points
    /// nearest each side. Points near a corner are left out, because a rounded
    /// corner would bend the line. Nil when the sides no longer make a sensible
    /// triangle.
    static func refinedTriangle(_ corners: [CGPoint], toward points: [CGPoint]) -> [CGPoint]? {
        let sides = (0..<3).map { (start: corners[$0], end: corners[($0 + 1) % 3]) }
        let shortest = sides.map { $0.start.distance(to: $0.end) }.min() ?? 0
        var members: [[CGPoint]] = [[], [], []]
        for point in points where corners.allSatisfy({ $0.distance(to: point) > 0.2 * shortest }) {
            let gaps = sides.map { segmentDistanceSquared(point, $0.start, $0.end) }
            members[gaps.indices.min { gaps[$0] < gaps[$1] } ?? 0].append(point)
        }
        let lines = sides.indices.map { side in
            members[side].count >= 3
                ? bestLine(through: members[side])
                : (point: sides[side].start, direction: sides[side].end - sides[side].start)
        }
        let refined = sides.indices.compactMap { intersection(lines[($0 + 2) % 3], lines[$0]) }
        guard refined.count == 3,
              abs(signedArea(refined)) > abs(signedArea(corners)) / 2,
              zip(refined, corners).allSatisfy({ $0.distance(to: $1) < shortest / 2 })
        else {
            return nil
        }
        return refined
    }

    static func bestLine(through points: [CGPoint]) -> (point: CGPoint, direction: CGPoint) {
        let center = mean(points)
        let spread = points.reduce(CGPoint.zero) { sum, point in
            let offset = point - center
            return sum + CGPoint(x: offset.x * offset.x - offset.y * offset.y, y: 2 * offset.x * offset.y)
        }
        let angle = atan2(spread.y, spread.x) / 2
        return (center, CGPoint(x: cos(angle), y: sin(angle)))
    }

    static func intersection(
        _ first: (point: CGPoint, direction: CGPoint),
        _ second: (point: CGPoint, direction: CGPoint)
    ) -> CGPoint? {
        let denominator = first.direction.cross(second.direction)
        let lengths = hypot(first.direction.x, first.direction.y) * hypot(second.direction.x, second.direction.y)
        // Sides within about 3 degrees of parallel meet too far away to trust.
        guard abs(denominator) > 0.05 * lengths else {
            return nil
        }
        return first.point + first.direction * ((second.point - first.point).cross(second.direction) / denominator)
    }

    /// The triangle turned so its most nearly level or upright side is exact,
    /// when that side is within the snap.
    static func levelled(_ corners: [CGPoint], _ tuning: Tuning) -> [CGPoint] {
        let turns = corners.indices.map { index in
            let edge = corners[(index + 1) % corners.count] - corners[index]
            let angle = atan2(edge.y, edge.x)
            return (angle / (.pi / 2)).rounded() * (.pi / 2) - angle
        }
        guard let turn = turns.min(by: { abs($0) < abs($1) }), abs(turn) <= tuning.axisSnap else {
            return corners
        }
        let center = mean(corners)
        return corners.map { center + ($0 - center).rotated(by: turn) }
    }
}

nonisolated extension ShapeRecognizer {
    static func nearestIndex(to point: CGPoint, in points: [CGPoint]) -> Int {
        var best = (index: 0, distance: CGFloat.infinity)
        for (index, candidate) in points.enumerated() {
            let gap = candidate - point
            if gap.dot(gap) < best.distance {
                best = (index, gap.dot(gap))
            }
        }
        return best.index
    }

    /// Least squares for `target = slope * source + intercept`.
    static func lineFit(_ source: [CGFloat], _ target: [CGFloat]) -> (slope: CGFloat, intercept: CGFloat)? {
        let count = CGFloat(source.count)
        let sourceMean = source.reduce(0, +) / count
        let targetMean = target.reduce(0, +) / count
        var covariance: CGFloat = 0
        var variance: CGFloat = 0
        for (x, y) in zip(source, target) {
            covariance += (x - sourceMean) * (y - targetMean)
            variance += (x - sourceMean) * (x - sourceMean)
        }
        guard variance > 0 else {
            return nil
        }
        let slope = covariance / variance
        return (slope, targetMean - slope * sourceMean)
    }

    /// Gaussian elimination with partial pivoting. Nil when the system is singular.
    static func solve(_ matrix: [[Double]], _ values: [Double]) -> [Double]? {
        var rows = zip(matrix, values).map { $0 + [$1] }
        let size = values.count
        for column in 0..<size {
            let pivot = (column..<size).max { abs(rows[$0][column]) < abs(rows[$1][column]) } ?? column
            guard abs(rows[pivot][column]) > 1e-12 else {
                return nil
            }
            rows.swapAt(column, pivot)
            for row in (column + 1)..<size {
                let factor = rows[row][column] / rows[column][column]
                for index in column...size {
                    rows[row][index] -= factor * rows[column][index]
                }
            }
        }
        var solution = [Double](repeating: 0, count: size)
        for row in (0..<size).reversed() {
            let known = ((row + 1)..<size).reduce(0) { $0 + rows[row][$1] * solution[$1] }
            solution[row] = (rows[row][size] - known) / rows[row][row]
        }
        return solution
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

    func rotated(by angle: CGFloat) -> CGPoint {
        CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }
}
