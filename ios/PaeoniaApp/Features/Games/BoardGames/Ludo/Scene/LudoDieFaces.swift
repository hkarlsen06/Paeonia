import Foundation
import simd

/// Which face of the die is where, and how to turn the die so a face points up.
/// The faces follow a real die: opposite faces add up to 7. In the die's own
/// frame the face 1 is on top (+y), 6 below, 2 toward +z, 5 toward -z, 3 toward
/// +x and 4 toward -x.
nonisolated enum LudoDieFaces {
    /// One face: the direction it points, and the directions along it for the pips.
    /// `down` is the direction that points toward the viewer once the face is on
    /// top, before the small landing turn, so a pip's heart point reads upright.
    struct Face: Equatable, Sendable {
        let normal: SIMD3<Float>
        let across: SIMD3<Float>
        let down: SIMD3<Float>
    }

    static func face(_ value: Int) -> Face {
        let back = lift(value).inverse
        return Face(
            normal: cleaned(back.act(SIMD3(0, 1, 0))),
            across: cleaned(back.act(SIMD3(1, 0, 0))),
            down: cleaned(back.act(SIMD3(0, 0, 1)))
        )
    }

    /// Rounds away the tiny errors of a quarter turn, so the directions are exact.
    private static func cleaned(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(vector.x.rounded(), vector.y.rounded(), vector.z.rounded())
    }

    /// Pip places on a face as (across, down) steps of -1, 0 or 1.
    static func pips(_ value: Int) -> [SIMD2<Float>] {
        let corners: [SIMD2<Float>] = [SIMD2(-1, -1), SIMD2(1, 1), SIMD2(1, -1), SIMD2(-1, 1)]
        switch value {
        case 1: return [.zero]
        case 2: return Array(corners[0..<2])
        case 3: return Array(corners[0..<2]) + [.zero]
        case 4: return corners
        case 5: return corners + [.zero]
        default: return corners + [SIMD2(-1, 0), SIMD2(1, 0)]
        }
    }

    /// The turn that puts face `value` on top, with a small turn around the
    /// vertical axis so the die looks placed and not aligned.
    static func orientation(showing value: Int) -> simd_quatf {
        let yaw = simd_quatf(angle: LudoSceneStyle.dieLandingYawRadians, axis: SIMD3(0, 1, 0))
        return yaw * lift(value)
    }

    /// The turn that carries face `value` to the top.
    static func lift(_ value: Int) -> simd_quatf {
        switch value {
        case 1: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        case 6: simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        case 2: simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        case 5: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        case 3: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        default: simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1))
        }
    }
}
