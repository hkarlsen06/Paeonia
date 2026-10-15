import Foundation
import simd

/// The board's slab and the candle flame.
nonisolated extension LudoMeshGeometry {
    /// One ring round the slab: how far in from the outline, how high, and how much the
    /// surface faces up there.
    private struct SlabRing {
        let inset: Float
        let height: Float
        let up: Float
    }

    /// A candle flame: a soft teardrop standing on its point, `flameHeight` tall.
    static func flame() -> LudoMeshData {
        let height = LudoSceneStyle.flameHeight
        let radius = LudoSceneStyle.flameWidth / 2
        let points: [(Float, Float)] = [(0, 0), (0.6, 0.1), (1, 0.32), (0.85, 0.58), (0.45, 0.84), (0, 1)]
        return turned(
            profile: smoothed(
                points.map { SIMD2($0.0 * radius, $0.1 * height) },
                samples: LudoSceneStyle.profileSamples
            ),
            segments: 16,
            closesTop: false
        )
    }

    /// The outline of a square `half` wide each way from the middle with corners rounded
    /// by `radius`, as (x, z) points and the outward direction at each, going round
    /// counterclockwise seen from above.
    static func roundedSquare(
        half: Float,
        radius: Float,
        cornerSegments: Int
    ) -> [(point: SIMD2<Float>, out: SIMD2<Float>)] {
        let middle = half - radius
        // Corners in turn: far right, far left, near left, near right. Seen from above with
        // z toward the viewer, the angle of a direction (x, z) runs from +x toward -z.
        let corners: [(SIMD2<Float>, Float)] = [
            (SIMD2(middle, -middle), 0), (SIMD2(-middle, -middle), .pi / 2),
            (SIMD2(-middle, middle), .pi), (SIMD2(middle, middle), 3 * .pi / 2)
        ]
        return corners.flatMap { center, start in
            (0...cornerSegments).map { step in
                let angle = start + Float(step) / Float(cornerSegments) * .pi / 2
                let out = SIMD2(cos(angle), -sin(angle))
                return (center + out * radius, out)
            }
        }
    }

    /// The board's slab without its flat top: a softly rounded top edge `edge` wide that
    /// runs into straight sides down to `thickness` below the top. Its top is at height 0.
    static func slabSides(half: Float, cornerRadius: Float, edge: Float, thickness: Float) -> LudoMeshData {
        let outline = roundedSquare(half: half, radius: cornerRadius, cornerSegments: LudoSceneStyle.slabCornerSegments)
        // The rings from the top edge round to the side, then the bottom.
        var rings = (0...LudoSceneStyle.slabEdgeSegments).map { step in
            let angle = Float(step) / Float(LudoSceneStyle.slabEdgeSegments) * .pi / 2
            return SlabRing(inset: edge * (1 - sin(angle)), height: -edge * (1 - cos(angle)), up: cos(angle))
        }
        rings.append(SlabRing(inset: 0, height: -thickness, up: 0))
        var data = LudoMeshData()
        let count = outline.count
        for ring in rings {
            let across = (1 - ring.up * ring.up).squareRoot()
            for (point, out) in outline {
                let position = point - out * ring.inset
                data.positions.append(SIMD3(position.x, ring.height, position.y))
                data.normals.append(simd_normalize(SIMD3(out.x * across, ring.up, out.y * across)))
                data.uvs.append(SIMD2((position.x / half + 1) / 2, (1 - position.y / half) / 2))
            }
        }
        for ring in 0..<(rings.count - 1) {
            for index in 0..<count {
                let next = (index + 1) % count
                let upperHere = UInt32(ring * count + index)
                let upperNext = UInt32(ring * count + next)
                let lowerHere = UInt32((ring + 1) * count + index)
                let lowerNext = UInt32((ring + 1) * count + next)
                data.indices += [upperHere, lowerHere, upperNext, upperNext, lowerHere, lowerNext]
            }
        }
        return data
    }

    /// The flat top of the board inside its rounded edge, facing up at height 0. Its
    /// picture covers `pictureHalf` each way from the middle, with the top row at the far edge.
    static func slabTop(half: Float, cornerRadius: Float, edge: Float, pictureHalf: Float) -> LudoMeshData {
        let outline = roundedSquare(
            half: half - edge,
            radius: cornerRadius - edge,
            cornerSegments: LudoSceneStyle.slabCornerSegments
        )
        var data = LudoMeshData()
        func add(_ point: SIMD2<Float>) {
            data.positions.append(SIMD3(point.x, 0, point.y))
            data.normals.append(SIMD3(0, 1, 0))
            data.uvs.append(SIMD2((point.x / pictureHalf + 1) / 2, (1 - point.y / pictureHalf) / 2))
        }
        add(.zero)
        for (point, _) in outline { add(point) }
        let count = UInt32(outline.count)
        for index in 0..<count {
            data.indices += [0, 1 + index, 1 + (index + 1) % count]
        }
        return data
    }
}
