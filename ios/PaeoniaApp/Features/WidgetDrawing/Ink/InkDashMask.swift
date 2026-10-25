import CoreGraphics

/// The ink a dashed or dotted line keeps, as a mask on one stroke.
///
/// Dashes are laid out by distance along the line from its first point, so
/// adding points at the end never moves a dash that is already drawn, and the
/// partner, who gets the same points, lays them out the same way.
nonisolated enum InkDashMask {
    /// How far apart the centerline samples are, in path points.
    static let sampleSpacing: CGFloat = 1

    /// Where each run of ink starts and ends, as distances along a line
    /// `length` long. The first run starts `phase` in, so the round end or
    /// dot drawn around it lies on the line. The last run may be cut short by
    /// the end of the line.
    static func runs(length: CGFloat, pattern: InkDashPattern, phase: CGFloat) -> [ClosedRange<CGFloat>] {
        stride(from: phase, through: length, by: pattern.period).map { start in
            start...min(start + pattern.on, length)
        }
    }

    /// The mask for a line through `centerline`, in the stroke's own space.
    /// A dash is its run of the line, `width` wide with round ends. A dot is
    /// a circle `width` across at the start of its run. A closed line, a
    /// snapped shape that ends where it starts, stretches the pattern a
    /// little so it meets itself where the line closes.
    static func path(centerline: [CGPoint], pattern: InkDashPattern, width: CGFloat, isClosed: Bool) -> CGPath {
        let distances = cumulativeDistances(centerline)
        let pieces = CGMutablePath()
        guard let length = distances.last else {
            return pieces
        }
        var pattern = pattern
        if isClosed, length > 0 {
            let stretch = length / (max(1, (length / pattern.period).rounded()) * pattern.period)
            pattern = InkDashPattern(on: pattern.on * stretch, period: pattern.period * stretch)
        }
        // Half a width in, the first round end or dot starts where the line
        // does. A line shorter than that keeps its one dot or dash.
        let phase = min(width / 2, length)
        var index = 0
        for run in runs(length: length, pattern: pattern, phase: phase) {
            while index + 1 < distances.count, distances[index + 1] < run.lowerBound {
                index += 1
            }
            let start = point(at: run.lowerBound, centerline, distances, from: index)
            if pattern.on == 0 {
                let radius = width / 2
                pieces.addEllipse(in: CGRect(x: start.x - radius, y: start.y - radius, width: width, height: width))
                continue
            }
            pieces.move(to: start)
            var next = index + 1
            while next < distances.count, distances[next] < run.upperBound {
                pieces.addLine(to: centerline[next])
                next += 1
            }
            pieces.addLine(to: point(at: run.upperBound, centerline, distances, from: index))
        }
        guard pattern.on > 0 else {
            return pieces
        }
        return pieces.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    private static func cumulativeDistances(_ points: [CGPoint]) -> [CGFloat] {
        var total: CGFloat = 0
        return points.indices.map { index in
            if index > 0 {
                total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            }
            return total
        }
    }

    /// The point `distance` along the line, searching from segment `start`.
    private static func point(
        at distance: CGFloat,
        _ points: [CGPoint],
        _ distances: [CGFloat],
        from start: Int
    ) -> CGPoint {
        var index = start
        while index + 1 < distances.count, distances[index + 1] < distance {
            index += 1
        }
        guard index + 1 < points.count else {
            return points[index]
        }
        let segment = distances[index + 1] - distances[index]
        let fraction = segment > 0 ? (distance - distances[index]) / segment : 0
        let from = points[index]
        let to = points[index + 1]
        return CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }
}
