import CoreGraphics
import Foundation
import simd

/// How far the camera has been turned and zoomed by the person's hands. The
/// camera orbits a point at the middle of the board. Yaw is free. Pitch is the
/// angle above the board and stays inside the orbit range. Zoom is a share of
/// the default distance. Pure math, so the camera is testable.
nonisolated struct LudoCameraPose: Equatable, Sendable {
    /// Radians around the vertical axis. 0 looks at the board from the front.
    var yaw = 0.0
    /// Radians above the board.
    var pitch = LudoCameraPose.defaultPitch
    /// 1 is the default distance.
    var zoom = 1.0

    static let defaultPitch = LudoSceneStyle.cameraPitchDegrees * .pi / 180
    static let pitchRange = (LudoSceneStyle.orbitPitchRangeDegrees.lowerBound * .pi / 180)...(
        LudoSceneStyle.orbitPitchRangeDegrees.upperBound * .pi / 180
    )

    static let home = LudoCameraPose()

    /// The same pose with pitch and zoom inside their limits and yaw within one turn.
    var clamped: LudoCameraPose {
        var pose = self
        pose.pitch = min(max(pitch, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        pose.zoom = min(max(zoom, LudoSceneStyle.zoomRange.lowerBound), LudoSceneStyle.zoomRange.upperBound)
        pose.yaw = yaw.remainder(dividingBy: 2 * .pi)
        return pose
    }

    /// A pose part of the way to another one. Yaw takes the short way round.
    func blended(to other: LudoCameraPose, amount: Double) -> LudoCameraPose {
        let turn = (other.yaw - yaw).remainder(dividingBy: 2 * .pi)
        return LudoCameraPose(
            yaw: yaw + turn * amount,
            pitch: pitch + (other.pitch - pitch) * amount,
            zoom: zoom + (other.zoom - zoom) * amount
        )
    }
}

/// How far the camera stands from the board and where it looks, for a view of one
/// shape. The board fills the view sideways, and its near edge may run a little
/// past the left and right edges. Pure math, so the fit is testable.
nonisolated struct LudoCameraFit: Equatable, Sendable {
    /// Distance from the target at zoom 1.
    let distance: Double
    /// Depth of the point the camera looks at and orbits, so the board sits in the middle of the view.
    let targetZ: Double
    /// Width divided by height of the view.
    let aspect: Double

    static func make(aspect rawAspect: Double) -> LudoCameraFit {
        let setup = Fit(aspect: max(rawAspect, 0.2))
        let targetZ = setup.centeredTargetZ()
        return LudoCameraFit(distance: setup.fittingDistance(targetZ: targetZ), targetZ: targetZ, aspect: setup.aspect)
    }

    /// Where the camera stands and looks for a pose.
    func rig(for pose: LudoCameraPose) -> LudoCameraRig {
        let pose = pose.clamped
        let target = SIMD3<Double>(0, 0, targetZ)
        let position = target + Self.offset(yaw: pose.yaw, pitch: pose.pitch) * (distance * pose.zoom)
        return LudoCameraRig(
            position: SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z)),
            target: SIMD3<Float>(Float(target.x), Float(target.y), Float(target.z)),
            fieldOfViewDegrees: Float(LudoSceneStyle.cameraFieldOfViewDegrees),
            aspect: aspect
        )
    }

    /// The unit direction from the target to the camera.
    fileprivate static func offset(yaw: Double, pitch: Double) -> SIMD3<Double> {
        SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
    }

    /// The numbers of one fit: the lens, the shape of the view and the corners to keep in view.
    private struct Fit {
        let aspect: Double
        let tanHalf = tan(LudoSceneStyle.cameraFieldOfViewDegrees / 2 * .pi / 180)
        let corners = Fit.fitPoints()

        private static let nearestDistance = 3.0
        private static let farthestDistance = 400.0
        private static let targetRange = 12.0

        /// The corners of the slab at the floor and at the height of the tallest thing on it.
        private static func fitPoints() -> [SIMD3<Double>] {
            let half = Double(LudoWorld.halfSlab)
            var points: [SIMD3<Double>] = []
            for height in [0, LudoSceneStyle.cameraExtraHeight] {
                for sign in [(-1.0, -1.0), (-1.0, 1.0), (1.0, -1.0), (1.0, 1.0)] {
                    points.append(SIMD3(sign.0 * half, height, sign.1 * half))
                }
            }
            return points
        }

        func cameraPosition(distance: Double, targetZ: Double) -> SIMD3<Double> {
            SIMD3(0, 0, targetZ) + LudoCameraFit.offset(yaw: 0, pitch: LudoCameraPose.defaultPitch) * distance
        }

        /// How far outside the allowed area the corners reach, 1 or less when they fit. Sideways
        /// the allowance is a little past the view's edge. Nil height means no corner is behind the camera.
        func extents(distance: Double, targetZ: Double) -> (largest: Double, centerY: Double) {
            let camera = cameraPosition(distance: distance, targetZ: targetZ)
            let target = SIMD3<Double>(0, 0, targetZ)
            var largest = 0.0
            var lowest = Double.infinity
            var highest = -Double.infinity
            for corner in corners {
                guard let ndc = LudoCameraRig.normalized(
                    corner, camera: camera, target: target, tanHalf: tanHalf, aspect: aspect
                ) else { return (.infinity, 0) }
                largest = max(
                    largest,
                    abs(ndc.x) / (1 + LudoSceneStyle.cameraOvershoot),
                    abs(ndc.y) / (1 - LudoSceneStyle.cameraMargin)
                )
                lowest = min(lowest, ndc.y)
                highest = max(highest, ndc.y)
            }
            return (largest, (lowest + highest) / 2)
        }

        /// The smallest distance at which every corner is inside the allowed area.
        func fittingDistance(targetZ: Double) -> Double {
            var near = Self.nearestDistance
            var far = Self.farthestDistance
            for _ in 0..<40 {
                let middle = (near + far) / 2
                if extents(distance: middle, targetZ: targetZ).largest <= 1 {
                    far = middle
                } else {
                    near = middle
                }
            }
            return far
        }

        func centerY(targetZ: Double) -> Double {
            extents(distance: fittingDistance(targetZ: targetZ), targetZ: targetZ).centerY
        }

        /// The target depth that puts the board in the middle of the view from top to bottom.
        func centeredTargetZ() -> Double {
            var low = -Self.targetRange
            var high = Self.targetRange
            let lowCenter = centerY(targetZ: low)
            let highCenter = centerY(targetZ: high)
            if lowCenter * highCenter > 0 {
                return abs(lowCenter) < abs(highCenter) ? low : high
            }
            for _ in 0..<30 {
                let middle = (low + high) / 2
                if centerY(targetZ: middle) * lowCenter > 0 {
                    low = middle
                } else {
                    high = middle
                }
            }
            return (low + high) / 2
        }
    }
}

/// Where the camera stands and looks. Also says where a point of the scene shows in the view.
nonisolated struct LudoCameraRig: Equatable, Sendable {
    let position: SIMD3<Float>
    let target: SIMD3<Float>
    let fieldOfViewDegrees: Float
    /// Width divided by height of the view.
    let aspect: Double

    /// The default camera for a view `aspect` wide for each unit of height.
    static func fitting(aspect: Double) -> LudoCameraRig {
        LudoCameraFit.make(aspect: aspect).rig(for: .home)
    }

    /// Where a point of the scene shows in the view, from 0 to 1 across and down,
    /// with (0, 0) at the top left. Nil when the point is behind the camera.
    func project(_ world: SIMD3<Float>) -> CGPoint? {
        let tanHalf = tan(Double(fieldOfViewDegrees) / 2 * .pi / 180)
        let camera = SIMD3<Double>(Double(position.x), Double(position.y), Double(position.z))
        let focus = SIMD3<Double>(Double(target.x), Double(target.y), Double(target.z))
        let point = SIMD3<Double>(Double(world.x), Double(world.y), Double(world.z))
        guard let ndc = Self.normalized(point, camera: camera, target: focus, tanHalf: tanHalf, aspect: aspect) else {
            return nil
        }
        return CGPoint(x: (ndc.x + 1) / 2, y: (1 - ndc.y) / 2)
    }

    /// Position in the view from -1 to 1 on each side, y up, for a camera that looks
    /// from `camera` at `target` with the vertical axis up. Nil behind the camera.
    fileprivate static func normalized(
        _ point: SIMD3<Double>,
        camera: SIMD3<Double>,
        target: SIMD3<Double>,
        tanHalf: Double,
        aspect: Double
    ) -> SIMD2<Double>? {
        let forward = simd_normalize(target - camera)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let offset = point - camera
        let depth = simd_dot(offset, forward)
        guard depth > 0.01 else { return nil }
        return SIMD2(
            simd_dot(offset, right) / depth / (tanHalf * aspect),
            simd_dot(offset, up) / depth / tanHalf
        )
    }
}
