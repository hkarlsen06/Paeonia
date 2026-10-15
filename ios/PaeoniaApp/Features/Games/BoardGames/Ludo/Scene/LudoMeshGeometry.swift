import Foundation
import simd

/// Triangles for one mesh, before RealityKit sees them.
nonisolated struct LudoMeshData: Equatable, Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
}

/// Builds the pawn, the peony bud and the mark disc from a profile. A profile is
/// a list of (radius, height) points from the bottom up that is turned around
/// the vertical axis. Pure math, so the shapes are testable.
nonisolated enum LudoMeshGeometry {
    /// A smooth curve through the profile points. Each gap gets `samples` extra points.
    static func smoothed(_ points: [SIMD2<Float>], samples: Int) -> [SIMD2<Float>] {
        guard points.count > 2, samples > 0 else { return points }
        var result: [SIMD2<Float>] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            for step in 0...samples {
                if step == samples && index < points.count - 2 { continue }
                let fraction = Float(step) / Float(samples)
                let linear: SIMD2<Float> = (p2 - p0) * fraction
                let quadraticTerms: SIMD2<Float> = 2 * p0 - 5 * p1 + 4 * p2 - p3
                let cubicTerms: SIMD2<Float> = 3 * p1 - p0 - 3 * p2 + p3
                let squared = fraction * fraction
                let sum: SIMD2<Float> = 2 * p1 + linear + quadraticTerms * squared + cubicTerms * (squared * fraction)
                let curve = sum * 0.5
                result.append(SIMD2(max(curve.x, 0), curve.y))
            }
        }
        return result
    }

    /// A shape turned around the vertical axis, by `sweep` radians from the +x
    /// direction toward +z. A full turn closes the ring. With `closesTop` a flat
    /// cap with an upward normal covers the last ring (full turns only).
    static func turned(
        profile: [SIMD2<Float>],
        segments: Int,
        sweep: Float = 2 * Float.pi,
        closesTop: Bool
    ) -> LudoMeshData {
        var data = LudoMeshData()
        guard profile.count >= 2, segments >= 3 else { return data }
        let isFull = sweep >= 2 * Float.pi - 0.0001
        let columns = isFull ? segments : segments + 1
        let normals = profileNormals(profile)
        for (ring, point) in profile.enumerated() {
            for segment in 0..<columns {
                let angle = sweep * Float(segment) / Float(segments)
                let (sine, cosine) = (sin(angle), cos(angle))
                data.positions.append(SIMD3(point.x * cosine, point.y, point.x * sine))
                data.normals.append(SIMD3(normals[ring].x * cosine, normals[ring].y, normals[ring].x * sine))
                data.uvs.append(SIMD2(Float(segment) / Float(segments), Float(ring) / Float(profile.count - 1)))
            }
        }
        for ring in 0..<(profile.count - 1) {
            for segment in 0..<segments {
                let next = isFull ? (segment + 1) % segments : segment + 1
                let lowerHere = UInt32(ring * columns + segment)
                let lowerNext = UInt32(ring * columns + next)
                let upperHere = UInt32((ring + 1) * columns + segment)
                let upperNext = UInt32((ring + 1) * columns + next)
                data.indices += [lowerHere, upperHere, lowerNext, lowerNext, upperHere, upperNext]
            }
        }
        if closesTop, isFull, let top = profile.last {
            appendFan(to: &data, radius: top.x, height: top.y, segments: segments, mapsTexture: false)
        }
        return data
    }

    /// A flat disc facing up, with texture coordinates that put the picture's
    /// center at the disc center. The picture's top edge points away from the
    /// viewer (negative z) unless `flipsVertically`.
    static func disc(radius: Float, segments: Int, flipsVertically: Bool) -> LudoMeshData {
        var data = LudoMeshData()
        appendFan(
            to: &data,
            radius: radius,
            height: 0,
            segments: segments,
            mapsTexture: true,
            flipsVertically: flipsVertically
        )
        return data
    }

    // MARK: Pieces

    /// The profile of a pawn: a wide foot, a thin waist, a round head and a flat top.
    /// Heights are shares of the pawn height.
    static func pawnProfile() -> [SIMD2<Float>] {
        let height = LudoSceneStyle.pawnHeight
        let base = LudoSceneStyle.pawnBaseRadius
        let waist = LudoSceneStyle.pawnWaistRadius
        let head = LudoSceneStyle.pawnHeadRadius
        let top = LudoSceneStyle.pawnTopRadius
        let points: [(Float, Float)] = [
            (base * 0.9, 0),
            (base, 0.08),
            (base * 0.88, 0.16),
            (base * 0.62, 0.26),
            (waist * 1.5, 0.37),
            (waist, 0.48),
            (waist * 1.25, 0.58),
            (head * 0.85, 0.65),
            (head, 0.74),
            (head * 0.93, 0.86),
            (top * 1.12, 0.96),
            (top, 1)
        ]
        return points.map { SIMD2($0.0, $0.1 * height) }
    }

    static func pawn() -> LudoMeshData {
        turned(
            profile: smoothed(pawnProfile(), samples: LudoSceneStyle.profileSamples),
            segments: LudoSceneStyle.turnedSegments,
            closesTop: true
        )
    }

    static var pawnTopHeight: Float { LudoSceneStyle.pawnHeight }

    /// One flat half of the middle, facing up, on the side of +z. Turn it half a circle for the other half.
    static func homeHalf() -> LudoMeshData {
        turned(
            profile: [SIMD2(LudoSceneStyle.homeDiameter / 2, 0), SIMD2(0, 0)],
            segments: LudoSceneStyle.turnedSegments,
            sweep: Float.pi,
            closesTop: false
        )
    }

    /// The outline of a heart with its point toward +z, `width` wide and centered.
    static func heartOutline(width: Float, points count: Int) -> [SIMD2<Float>] {
        let raw: [SIMD2<Float>] = (0..<count).map { index in
            let angle = 2 * Float.pi * Float(index) / Float(count)
            let x = 16 * pow(sin(angle), 3)
            let y = 13 * cos(angle) - 5 * cos(2 * angle) - 2 * cos(3 * angle) - cos(4 * angle)
            return SIMD2(x, y)
        }
        let lowest = raw.map(\.y).min() ?? 0
        let highest = raw.map(\.y).max() ?? 0
        let middle = (lowest + highest) / 2
        let scale = width / 32
        // The heart's point is at the lowest y. Flip it so the point faces +z.
        return raw.map { SIMD2($0.x * scale, -($0.y - middle) * scale) }
    }

    /// A small raised heart for a pip, lying in the x and z plane with its point
    /// toward +z. It is a pillow: the edge meets the face and the middle rises.
    static func heart() -> LudoMeshData {
        let outline = heartOutline(width: LudoSceneStyle.pipWidth, points: 36)
        let rings = LudoSceneStyle.pipRings
        let raised = LudoSceneStyle.pipHeight
        var grid: [[SIMD3<Float>]] = []
        for ring in 0...rings {
            let angle = Float.pi / 2 * Float(ring) / Float(rings)
            let scale = cos(angle)
            let height = raised * sin(angle)
            grid.append(outline.map { SIMD3($0.x * scale, height, $0.y * scale) })
        }
        var data = LudoMeshData()
        let columns = outline.count
        for (row, points) in grid.enumerated() {
            for (column, position) in points.enumerated() {
                data.positions.append(position)
                data.normals.append(gridNormal(grid, row: row, column: column))
                data.uvs.append(SIMD2(Float(column) / Float(columns), Float(row) / Float(rings)))
            }
        }
        for row in 0..<rings {
            for column in 0..<columns {
                let next = (column + 1) % columns
                let lowerHere = UInt32(row * columns + column)
                let lowerNext = UInt32(row * columns + next)
                let upperHere = UInt32((row + 1) * columns + column)
                let upperNext = UInt32((row + 1) * columns + next)
                data.indices += [lowerHere, upperHere, lowerNext, lowerNext, upperHere, upperNext]
            }
        }
        return data
    }

    /// The normal of a vertex on a grid of rings, from its neighbors. It points up.
    private static func gridNormal(_ grid: [[SIMD3<Float>]], row: Int, column: Int) -> SIMD3<Float> {
        let columns = grid[row].count
        let around = grid[row][(column + 1) % columns] - grid[row][(column + columns - 1) % columns]
        let outward = grid[min(row + 1, grid.count - 1)][column] - grid[max(row - 1, 0)][column]
        var normal = simd_cross(outward, around)
        if simd_length(normal) < 1e-6 { return SIMD3(0, 1, 0) }
        normal = simd_normalize(normal)
        return normal.y < 0 ? -normal : normal
    }

    // MARK: Helpers

    /// The outward normal of each profile point, from the points around it.
    static func profileNormals(_ profile: [SIMD2<Float>]) -> [SIMD2<Float>] {
        profile.indices.map { index in
            let before = profile[max(index - 1, 0)]
            let after = profile[min(index + 1, profile.count - 1)]
            let tangent = after - before
            // Walking up, the outside is to the right of the direction of travel.
            let normal = SIMD2(tangent.y, -tangent.x)
            let length = simd_length(normal)
            return length > 1e-6 ? normal / length : SIMD2(1, 0)
        }
    }

    private static func appendFan(
        to data: inout LudoMeshData,
        radius: Float,
        height: Float,
        segments: Int,
        mapsTexture: Bool,
        flipsVertically: Bool = false
    ) {
        let first = UInt32(data.positions.count)
        func uv(x: Float, depth: Float) -> SIMD2<Float> {
            guard mapsTexture, radius > 0 else { return .zero }
            let across = 0.5 + x / (2 * radius)
            // Toward the viewer is depth > 0, which is the bottom of the picture.
            let up = 0.5 + (flipsVertically ? 1 : -1) * depth / (2 * radius)
            return SIMD2(across, up)
        }
        data.positions.append(SIMD3(0, height, 0))
        data.normals.append(SIMD3(0, 1, 0))
        data.uvs.append(uv(x: 0, depth: 0))
        for segment in 0..<segments {
            let angle = 2 * Float.pi * Float(segment) / Float(segments)
            let (x, depth) = (radius * cos(angle), radius * sin(angle))
            data.positions.append(SIMD3(x, height, depth))
            data.normals.append(SIMD3(0, 1, 0))
            data.uvs.append(uv(x: x, depth: depth))
        }
        for segment in 0..<segments {
            let current = first + 1 + UInt32(segment)
            let next = first + 1 + UInt32((segment + 1) % segments)
            data.indices += [first, next, current]
        }
    }
}
