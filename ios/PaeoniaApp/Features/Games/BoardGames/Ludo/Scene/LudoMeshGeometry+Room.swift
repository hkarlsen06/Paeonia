import Foundation
import simd

/// The cloth and the mugs on the table: a runner that hangs over both ends of the table,
/// a stoneware mug turned from one profile with a half ring for its handle, and the hot
/// chocolate in it.
nonisolated extension LudoMeshGeometry {
    /// The profile of a mug from the middle of its foot, up the outside, over the rim,
    /// down the inside and in across its floor. The inner faces get normals that point
    /// into the mug, since the profile walks down there.
    static func mugProfile() -> [SIMD2<Float>] {
        let style = LudoSceneStyle.self
        let radius = style.mugRadius
        let height = style.mugHeight
        let inner = radius - style.mugWall
        let lip = style.mugWall / 2
        return [
            SIMD2(0, 0),
            SIMD2(radius * 0.86, 0),
            SIMD2(radius * 0.97, 0.06),
            SIMD2(radius, 0.22),
            SIMD2(radius, height * 0.6),
            SIMD2(radius * 0.99, height - lip),
            SIMD2(radius - lip, height),
            SIMD2(inner * 1.01, height - lip),
            SIMD2(inner, height * 0.6),
            SIMD2(inner * 0.97, style.mugFloor + 0.1),
            SIMD2(inner * 0.86, style.mugFloor),
            SIMD2(0, style.mugFloor)
        ]
    }

    static func mug() -> LudoMeshData {
        turned(profile: smoothed(mugProfile(), samples: 2), segments: 40, closesTop: false)
    }

    /// The hot chocolate in a mug: flat in the middle, climbing the wall a little at its
    /// edge as liquid does. The texture's x runs from the middle (0) to the wall (1).
    static func cocoa() -> LudoMeshData {
        let style = LudoSceneStyle.self
        let edge = (style.mugRadius - style.mugWall) * 1.004
        let rise = style.cocoaMeniscus
        // Walking in from the wall, the surface's normals point up.
        let profile: [SIMD2<Float>] = [
            SIMD2(edge, rise),
            SIMD2(edge * 0.98, rise * 0.62),
            SIMD2(edge * 0.95, rise * 0.36),
            SIMD2(edge * 0.9, rise * 0.17),
            SIMD2(edge * 0.82, rise * 0.05),
            SIMD2(edge * 0.72, 0),
            SIMD2(edge * 0.5, 0),
            SIMD2(0, 0)
        ]
        var data = turned(profile: profile, segments: 40, closesTop: false)
        data.uvs = data.positions.map { SIMD2(min(simd_length(SIMD2($0.x, $0.z)) / edge, 1), 0.5) }
        return data
    }

    /// The handle: half of a ring of round section, lying flat on the side of +z with
    /// its ends on the x axis. Stand it up and press its ends into the mug's side.
    static func mugHandle() -> LudoMeshData {
        let style = LudoSceneStyle.self
        let thickness = style.mugHandleThickness
        let section: [SIMD2<Float>] = (0...16).map { step in
            let angle = 2 * Float.pi * Float(step) / 16
            return SIMD2(style.mugHandleRadius + thickness * cos(angle), thickness * sin(angle))
        }
        return turned(profile: section, segments: 20, sweep: .pi, closesTop: false)
    }

    // MARK: Runner

    /// A linen runner `runnerWidth` wide that lies on a table `tableDepth` long, with its
    /// top at height 0, wraps over both ends and hangs `runnerDrop` down. The hanging
    /// ends bulge out in soft folds and their hems are a little uneven, and the long
    /// edges wave a little. The texture's y runs along the cloth from one hem to the other.
    static func runner() -> LudoMeshData {
        let style = LudoSceneStyle.self
        let path = runnerPath()
        let across = 14
        var grid: [[SIMD3<Float>]] = []
        for step in path {
            grid.append((0...across).map { column in
                let share = Float(column) / Float(across) - 0.5
                var x = share * style.runnerWidth
                var depth = step.point.x
                var height = step.point.y
                // The long edges wave a little along the table.
                x *= 1 + 0.008 * sin(depth * 0.55 + 0.7) + 0.005 * sin(depth * 1.3)
                if step.hang > 0 {
                    // Folds only ever bulge outward, so the cloth never cuts into the table's edge.
                    let wave = 0.5 + 0.3 * sin(x * 1.9 + step.side) + 0.2 * sin(x * 3.4 + 1.1)
                    depth += step.side * style.runnerFold * step.hang * wave
                    x *= 1 + 0.03 * step.hang
                    height -= step.hang * step.hang * 0.08 * (1 + sin(x * 0.9 + step.side * 0.8))
                }
                return SIMD3(x, height, depth)
            })
        }
        var data = LudoMeshData()
        let lengths = path.map(\.distance)
        let total = lengths.last ?? 1
        for row in grid.indices {
            for column in grid[row].indices {
                data.positions.append(grid[row][column])
                data.normals.append(clothNormal(grid, row: row, column: column))
                data.uvs.append(SIMD2(Float(column) / Float(across), lengths[row] / total))
            }
        }
        let columns = across + 1
        for row in 0..<(grid.count - 1) {
            for column in 0..<across {
                let here = UInt32(row * columns + column)
                let right = here + 1
                let below = here + UInt32(columns)
                data.indices += [here, below, right, right, below, below + 1]
            }
        }
        return data
    }

    /// The runner's length from one hem to the other, as (z, height) points with how far
    /// down the hanging part each is (0 on the table, 1 at the hem), which end it is on,
    /// and the distance along the cloth.
    private struct ClothStep {
        let point: SIMD2<Float>
        let hang: Float
        let side: Float
        var distance: Float = 0
    }

    private static func runnerPath() -> [ClothStep] {
        let style = LudoSceneStyle.self
        let end = style.tableDepth / 2
        let wrap: Float = 0.08
        let hangRows = 10
        let wrapRows = 5
        let flatRows = 44
        // The near end, from the edge of the table down to the hem.
        var near: [ClothStep] = (0...wrapRows).map { step in
            let angle = Float.pi / 2 * (1 - Float(step) / Float(wrapRows))
            return ClothStep(point: SIMD2(end + wrap * cos(angle), -wrap + wrap * sin(angle)), hang: 0, side: 1)
        }
        near += (1...hangRows).map { step in
            let hang = Float(step) / Float(hangRows)
            return ClothStep(point: SIMD2(end + wrap, -wrap - (style.runnerDrop - wrap) * hang), hang: hang, side: 1)
        }
        let far = near.reversed().map { ClothStep(point: SIMD2(-$0.point.x, $0.point.y), hang: $0.hang, side: -1) }
        let flat = (1..<flatRows).map { step in
            ClothStep(point: SIMD2(-end + 2 * end * Float(step) / Float(flatRows), 0), hang: 0, side: 0)
        }
        var path = far + flat + near
        for index in path.indices.dropFirst() {
            path[index].distance = path[index - 1].distance + simd_distance(path[index].point, path[index - 1].point)
        }
        return path
    }

    /// The normal of a cloth vertex from its neighbors, on the side that faces away from
    /// the table: up on top and outward where it hangs.
    private static func clothNormal(_ grid: [[SIMD3<Float>]], row: Int, column: Int) -> SIMD3<Float> {
        let along = grid[min(row + 1, grid.count - 1)][column] - grid[max(row - 1, 0)][column]
        let across = grid[row][min(column + 1, grid[row].count - 1)] - grid[row][max(column - 1, 0)]
        let normal = simd_cross(along, across)
        return simd_length(normal) < 1e-6 ? SIMD3(0, 1, 0) : simd_normalize(normal)
    }
}
