import CoreGraphics
import Foundation

/// A clean shape a rough stroke snapped to. It carries where its outline
/// starts and which way it runs, so the outline is the same on both phones.
nonisolated struct SnappedShape: Equatable, Codable, Sendable {
    nonisolated enum Kind: Equatable, Codable, Sendable {
        case line(from: CGPoint, to: CGPoint)
        /// A curve from `from` to `to` that bends toward `control`, a
        /// quadratic Bézier curve. Its ends never meet.
        case arc(from: CGPoint, control: CGPoint, to: CGPoint)
        /// A circle has equal radii.
        case ellipse(center: CGPoint, radii: CGSize, rotation: CGFloat)
        /// The corners of a triangle (3) or a rectangle (4).
        case polygon([CGPoint])
        // swiftlint:disable enum_case_associated_values_count
        /// Upright, the notch is at the top (small y) and the tip at the bottom.
        case heart(center: CGPoint, size: CGSize, rotation: CGFloat, shape: HeartShape)
        // swiftlint:enable enum_case_associated_values_count
    }

    /// A heart's proportions, fitted to each stroke, since people draw the
    /// notch shallow or deep, the sides short or long, and the tip off to one
    /// side.
    nonisolated struct HeartShape: Equatable, Codable, Sendable {
        /// How far each lobe's center sits from the middle, in lobe radii.
        /// The lobes meet lower as it grows: at 0.71 just below the top, as
        /// emoji show, and at 0.99 almost as low as the lobe centers.
        var spread: CGFloat
        /// How far the tip sits below the lobe centers, in lobe radii.
        var tipDepth: CGFloat
        /// How far the outline shifts sideways per unit down, which moves the
        /// tip off the line below the notch.
        var lean: CGFloat = 0

        static let spreads: ClosedRange<CGFloat> = 0.5...0.99
        static let tipDepths: ClosedRange<CGFloat> = 1.8...5
        static let leans: ClosedRange<CGFloat> = -0.25...0.25

        var isValid: Bool {
            Self.spreads.contains(spread) && Self.tipDepths.contains(tipDepth) && Self.leans.contains(lean)
        }

        /// The outline in the unit square around the origin, before it is
        /// sized and turned.
        var template: [CGPoint] {
            SnappedShape.heartTemplate(spread: spread, tipDepth: tipDepth).map {
                CGPoint(x: $0.x + lean * $0.y, y: $0.y)
            }
        }
    }

    var kind: Kind
    /// Where a closed outline starts, as a fraction of the way around the
    /// kind's contour. A line or an arc starts at one of its ends.
    var start: CGFloat = 0
    /// The outline runs against the kind's contour. A reversed line or arc
    /// runs from `to` to `from`.
    var isReversed = false

    var isClosed: Bool { kind.isClosed }

    /// Points `spacing` apart along the outline, starting at `start` and
    /// running the stored way. Corners (polygon corners, the heart's notch and
    /// tip) appear three times in a row so a B-spline through the points
    /// keeps them sharp. A closed outline ends back at its start point.
    func outline(spacing: CGFloat) -> [CGPoint] {
        let contour = kind.contour
        var route = contour.isClosed ? contour.loop(startingAt: start) : contour.vertices
        if isReversed {
            route.reverse()
        }
        var outline = Array(repeating: route[0].point, count: route[0].isCorner ? 3 : 1)
        var piece = [route[0].point]
        for (index, vertex) in route.enumerated().dropFirst() {
            piece.append(vertex.point)
            guard vertex.isCorner || index == route.count - 1 else {
                continue
            }
            outline += Polyline.evenlySpaced(piece, spacing: spacing).dropFirst()
            if vertex.isCorner {
                outline += [vertex.point, vertex.point]
            }
            piece = [vertex.point]
        }
        // The canvas reads a stroke of one or two points as a fill tap.
        while outline.count < 3 {
            outline.append(outline[outline.count - 1])
        }
        return outline
    }
}

nonisolated extension SnappedShape {
    /// A resize never makes a shape smaller than the recognizer needs to see
    /// one at all.
    static let minimumSize = ShapeRecognizer.Tuning.standard.minimumSize

    /// The shape after the finger that held at `grab` when it snapped moved
    /// to `finger`. A closed shape scales about its center (a polygon's is
    /// its corners' mean) by how much farther from the center the finger is.
    /// A line or an arc keeps its start, and its far end moves as the finger
    /// does. An arc turns and scales about its start to keep its bend. The
    /// outline keeps its start and direction, so dashes stay where they were.
    func resized(grabbedAt grab: CGPoint, draggedTo finger: CGPoint) -> SnappedShape {
        func factor(about center: CGPoint) -> CGFloat {
            let grabDistance = grab.distance(to: center)
            guard grabDistance >= 1 else {
                return 1
            }
            let smallest = min(1, Self.minimumSize / ShapeRecognizer.boundingDiagonal(kind.contour.points))
            return max(finger.distance(to: center) / grabDistance, smallest)
        }

        func farEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
            var reach = end + (finger - grab) - start
            let length = hypot(reach.x, reach.y)
            if length < Self.minimumSize {
                let direction = length > 0 ? reach : end - start
                reach = direction * (Self.minimumSize / max(hypot(direction.x, direction.y), .ulpOfOne))
            }
            return start + reach
        }

        var shape = self
        switch kind {
        case let .line(from, to):
            let (start, end) = isReversed ? (to, from) : (from, to)
            let newEnd = farEnd(from: start, to: end)
            shape.kind = isReversed ? .line(from: newEnd, to: start) : .line(from: start, to: newEnd)
        case let .arc(from, control, to):
            let (start, end) = isReversed ? (to, from) : (from, to)
            let newEnd = farEnd(from: start, to: end)
            let newControl = Self.turned(control, about: start, carrying: end, to: newEnd)
            shape.kind = isReversed
                ? .arc(from: newEnd, control: newControl, to: start)
                : .arc(from: start, control: newControl, to: newEnd)
        case let .ellipse(center, radii, rotation):
            shape.kind = .ellipse(center: center, radii: radii * factor(about: center), rotation: rotation)
        case let .heart(center, size, rotation, heart):
            shape.kind = .heart(center: center, size: size * factor(about: center), rotation: rotation, shape: heart)
        case let .polygon(corners):
            let center = corners.reduce(.zero, +) * (1 / CGFloat(corners.count))
            let scale = factor(about: center)
            shape.kind = .polygon(corners.map { center + ($0 - center) * scale })
        }
        return shape
    }
}

private nonisolated extension SnappedShape {
    /// `point` after the turn and scale about `start` that carry `old` to
    /// `new`, as complex numbers: start + (point - start) * (new - start) / (old - start).
    static func turned(_ point: CGPoint, about start: CGPoint, carrying old: CGPoint, to new: CGPoint) -> CGPoint {
        let from = old - start
        let to = new - start
        let lengthSquared = from.x * from.x + from.y * from.y
        let turn = CGPoint(
            x: (to.x * from.x + to.y * from.y) / lengthSquared,
            y: (to.y * from.x - to.x * from.y) / lengthSquared
        )
        let offset = point - start
        return start + CGPoint(x: offset.x * turn.x - offset.y * turn.y, y: offset.x * turn.y + offset.y * turn.x)
    }
}

nonisolated extension SnappedShape {
    /// Refuses a shape that cannot be drawn, so a bad message from the
    /// partner's phone fails to decode instead of crashing the outline.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        start = try container.decode(CGFloat.self, forKey: .start)
        isReversed = try container.decode(Bool.self, forKey: .isReversed)
        guard kind.isDrawable, (0...1).contains(start) else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Undrawable shape")
            throw DecodingError.dataCorrupted(context)
        }
    }
}

nonisolated extension SnappedShape {
    /// A kind's points in their own order, before a stroke picks where the
    /// outline starts and which way it runs.
    struct Contour {
        struct Vertex {
            var point: CGPoint
            var isCorner: Bool
        }

        var points: [CGPoint]
        var corners: Set<Int>
        var isClosed: Bool

        var vertices: [Vertex] {
            points.indices.map { Vertex(point: points[$0], isCorner: corners.contains($0)) }
        }

        /// The closed contour cut open `fraction` of the way around, as a
        /// route that starts and ends at that point.
        func loop(startingAt fraction: CGFloat) -> [Vertex] {
            let count = points.count
            var lengths: [CGFloat] = [0]
            for index in 0..<count {
                lengths.append(lengths[index] + points[index].distance(to: points[(index + 1) % count]))
            }
            let target = (fraction - fraction.rounded(.down)) * lengths[count]
            let edge = min(count - 1, lengths.lastIndex { $0 <= target } ?? 0)
            let edgeLength = lengths[edge + 1] - lengths[edge]
            let along = edgeLength > 0 ? (target - lengths[edge]) / edgeLength : 0
            let startPoint = points[edge].interpolated(to: points[(edge + 1) % count], by: along)
            let start = Vertex(point: startPoint, isCorner: false)
            let around = (1...count).map { step in
                let index = (edge + step) % count
                return Vertex(point: points[index], isCorner: corners.contains(index))
            }

            // The start can land on a corner. Merging the copies keeps it one
            // corner, sharp at both ends of the loop.
            var merged: [Vertex] = []
            for vertex in [start] + around + [start] {
                if let last = merged.last, last.point.distance(to: vertex.point) < 1e-6 {
                    merged[merged.count - 1] = vertex.isCorner ? vertex : last
                } else {
                    merged.append(vertex)
                }
            }
            if !merged[0].isCorner, merged[merged.count - 1].isCorner {
                merged[0] = merged[merged.count - 1]
            }
            merged[merged.count - 1] = merged[0]
            return merged
        }
    }

    /// Points on a curved contour. Even, so the heart's tip lands on a point.
    static let curveCount = 256

    /// Two circles of radius 1, centered `spread` either side of the middle,
    /// with straight sides from the tip `tipDepth` below their centers that
    /// meet the circles at a tangent. Spread evenly along its length and fitted
    /// to the unit square around the origin, it starts at the notch, runs over
    /// the right lobe and down to the tip at its middle point, and comes back
    /// up the left side. A spread of 0.71 and a depth of 2.1 make a square
    /// turned 45 degrees with half circles on its two upper sides.
    static func heartTemplate(spread: CGFloat, tipDepth: CGFloat) -> [CGPoint] {
        let lobeCenter = CGPoint(x: spread, y: 0)
        let tip = CGPoint(x: 0, y: tipDepth)
        let toTip = tip - lobeCenter
        let tangent = atan2(toTip.y, toTip.x) - acos(1 / hypot(toTip.x, toTip.y))
        let notch = -acos(-spread)
        var rightSide = (0...512).map { step in
            let angle = notch + (tangent - notch) * CGFloat(step) / 512
            return lobeCenter + CGPoint(x: cos(angle), y: sin(angle))
        }
        rightSide.append(tip)
        let right = Polyline.resampled(rightSide, count: curveCount / 2 + 1)
        let left = right.dropFirst().dropLast().reversed().map { CGPoint(x: -$0.x, y: $0.y) }
        let width = 2 * (spread + 1)
        let height = tipDepth + 1
        return (right + left).map { CGPoint(x: $0.x / width, y: ($0.y - (tipDepth - 1) / 2) / height) }
    }
}

nonisolated extension SnappedShape.Kind {
    /// Finite numbers no farther than 10,000 points from the origin, which
    /// keeps the outline a sane size, and real corners and radii.
    var isDrawable: Bool {
        let numbers: [CGFloat]
        let isWellFormed: Bool
        switch self {
        case let .line(from, to):
            numbers = [from.x, from.y, to.x, to.y]
            isWellFormed = true
        case let .arc(from, control, to):
            numbers = [from.x, from.y, control.x, control.y, to.x, to.y]
            // Resizing turns the arc about its start by where its end goes.
            isWellFormed = from != to
        case let .ellipse(center, radii, rotation):
            numbers = [center.x, center.y, radii.width, radii.height, rotation]
            isWellFormed = radii.width > 0 && radii.height > 0
        case let .heart(center, size, rotation, shape):
            numbers = [center.x, center.y, size.width, size.height, rotation]
            isWellFormed = size.width > 0 && size.height > 0 && shape.isValid
        case let .polygon(corners):
            numbers = corners.flatMap { [$0.x, $0.y] }
            isWellFormed = (3...4).contains(corners.count)
        }
        return isWellFormed && numbers.allSatisfy { $0.isFinite && abs($0) <= 10_000 }
    }

    var isClosed: Bool {
        switch self {
        case .line, .arc: false
        case .ellipse, .polygon, .heart: true
        }
    }

    var contour: SnappedShape.Contour {
        switch self {
        case let .line(from, to):
            return .init(points: [from, to], corners: [], isClosed: false)
        case let .arc(from, control, to):
            let count = SnappedShape.curveCount / 2
            let points = (0...count).map { index in
                let along = CGFloat(index) / CGFloat(count)
                let before: CGFloat = 1 - along
                let pull: CGPoint = control * (2 * along * before)
                return from * (before * before) + pull + to * (along * along)
            }
            return .init(points: points, corners: [], isClosed: false)
        case let .ellipse(center, radii, rotation):
            let count = SnappedShape.curveCount
            let points = (0..<count).map { index in
                let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
                return center + CGPoint(x: radii.width * cos(angle), y: radii.height * sin(angle)).rotated(by: rotation)
            }
            return .init(points: points, corners: [], isClosed: true)
        case let .polygon(corners):
            return .init(points: corners, corners: Set(corners.indices), isClosed: true)
        case let .heart(center, size, rotation, shape):
            let points = shape.template.map {
                center + CGPoint(x: $0.x * size.width, y: $0.y * size.height).rotated(by: rotation)
            }
            return .init(points: points, corners: [0, points.count / 2], isClosed: true)
        }
    }
}

/// Spacing points evenly along a polyline, for the outline and the recognizer.
nonisolated enum Polyline {
    /// `count` points evenly spaced along `points`. An open polyline keeps
    /// both ends. A closed one starts at the first point and stops one step
    /// short of it.
    static func resampled(_ points: [CGPoint], count: Int, isClosed: Bool = false) -> [CGPoint] {
        let path = isClosed ? points + [points[0]] : points
        guard path.count >= 2, count >= 2 else {
            return Array(repeating: points[0], count: max(count, 1))
        }
        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(path.count)
        for index in 1..<path.count {
            lengths.append(lengths[index - 1] + path[index - 1].distance(to: path[index]))
        }
        let step = lengths[lengths.count - 1] / CGFloat(isClosed ? count : count - 1)
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var segment = 0
        for sample in 0..<count {
            let target = CGFloat(sample) * step
            while segment < path.count - 2, lengths[segment + 1] < target {
                segment += 1
            }
            let span = lengths[segment + 1] - lengths[segment]
            let along = span > 0 ? min(1, max(0, (target - lengths[segment]) / span)) : 0
            result.append(path[segment].interpolated(to: path[segment + 1], by: along))
        }
        if !isClosed {
            result[count - 1] = path[path.count - 1]
        }
        return result
    }

    /// Both ends of `points` and evenly spaced points between them, as close
    /// to `spacing` apart as a whole number of steps allows.
    static func evenlySpaced(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        var length: CGFloat = 0
        for index in points.indices.dropFirst() {
            length += points[index - 1].distance(to: points[index])
        }
        let steps = max(1, Int((length / spacing).rounded()))
        return resampled(points, count: steps + 1)
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

fileprivate nonisolated extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
