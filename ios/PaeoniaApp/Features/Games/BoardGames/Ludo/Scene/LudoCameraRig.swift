import CoreGraphics
import Foundation
import simd

/// How far the camera has been zoomed, turned and slid by the person's hands. The
/// camera looks at a point on the board, the middle unless a pinch slid it. Yaw is
/// free and turns with a two-finger twist. Pitch stays at its default. Zoom is a share
/// of the default distance. Pure math, so the camera is testable.
nonisolated struct LudoCameraPose: Equatable, Sendable {
    /// Radians around the vertical axis. 0 looks at the board from the front.
    var yaw = LudoCameraPose.defaultYaw
    /// Radians above the board.
    var pitch = LudoCameraPose.defaultPitch
    /// 1 is the default distance.
    var zoom = 1.0
    /// How far the point the camera looks at has slid from the middle of the board,
    /// in cells across (x) and toward the viewer (y).
    var pan = SIMD2<Double>.zero

    static let defaultPitch = LudoSceneStyle.cameraPitchDegrees * .pi / 180
    static let defaultYaw = LudoSceneStyle.cameraYawDegrees * .pi / 180

    static let home = LudoCameraPose()

    /// The same pose with zoom and pan inside their limits and yaw within one turn.
    /// The pan may reach further the closer the camera is, and none at zoom 1 or out,
    /// so zooming out brings the board back to the middle.
    var clamped: LudoCameraPose {
        var pose = self
        pose.zoom = min(max(zoom, LudoSceneStyle.zoomRange.lowerBound), LudoSceneStyle.zoomRange.upperBound)
        pose.yaw = yaw.remainder(dividingBy: 2 * .pi)
        let closeness = (1 - pose.zoom) / (1 - LudoSceneStyle.zoomRange.lowerBound)
        let reach = LudoSceneStyle.panReach * max(closeness, 0)
        pose.pan = simd_clamp(pan, SIMD2(repeating: -reach), SIMD2(repeating: reach))
        return pose
    }

    /// A pose part of the way to another one. Yaw takes the short way round.
    func blended(to other: LudoCameraPose, amount: Double) -> LudoCameraPose {
        let turn = (other.yaw - yaw).remainder(dividingBy: 2 * .pi)
        return LudoCameraPose(
            yaw: yaw + turn * amount,
            pitch: pitch + (other.pitch - pitch) * amount,
            zoom: zoom + (other.zoom - zoom) * amount,
            pan: pan + (other.pan - pan) * amount
        )
    }
}

/// How far the camera stands from the board and where it looks, for a view of one
/// shape. The board and the props round it fit inside the view, so nothing important
/// sits under the rows above and below. Pure math, so the fit is testable.
nonisolated struct LudoCameraFit: Equatable, Sendable {
    /// Distance from the target at zoom 1.
    let distance: Double
    /// Depth of the point the camera looks at at zero pan, so the board sits in the middle of the view.
    let targetZ: Double
    /// Width divided by height of the view.
    let aspect: Double
    /// The share of the view's height, around its middle, the board fits in. Below 1
    /// when the view reaches past the space the board was given, as Ludo's does.
    let fitHeight: Double

    static func make(aspect rawAspect: Double, fitHeight: Double = 1) -> LudoCameraFit {
        let setup = Fit(aspect: max(rawAspect, 0.2), fitHeight: min(max(fitHeight, 0.1), 1))
        let targetZ = setup.centeredTargetZ()
        return LudoCameraFit(
            distance: setup.fittingDistance(targetZ: targetZ),
            targetZ: targetZ,
            aspect: setup.aspect,
            fitHeight: setup.fitHeight
        )
    }

    /// Where the camera stands and looks for a pose.
    func rig(for pose: LudoCameraPose) -> LudoCameraRig {
        let pose = pose.clamped
        let target = SIMD3<Double>(pose.pan.x, 0, targetZ + pose.pan.y)
        let position = target + Self.offset(yaw: pose.yaw, pitch: pose.pitch) * (distance * pose.zoom)
        return LudoCameraRig(
            position: SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z)),
            target: SIMD3<Float>(Float(target.x), Float(target.y), Float(target.z)),
            fieldOfViewDegrees: Float(LudoSceneStyle.cameraFieldOfViewDegrees),
            aspect: aspect
        )
    }

    /// The pose at `zoom`, slid so the board point `anchor` shows at `point` (0 to 1
    /// across and down). A pinch uses it to keep the board under the fingers. The pan
    /// limit wins when the two disagree.
    func pose(
        _ pose: LudoCameraPose,
        zoom: Double,
        keeping anchor: SIMD2<Double>,
        at point: CGPoint
    ) -> LudoCameraPose {
        var result = pose
        result.zoom = zoom
        result = result.clamped
        // Sliding the camera along the board slides every board point under it by the same amount.
        if let now = rig(for: result).boardPoint(at: point) {
            result.pan += anchor - now
        }
        return result.clamped
    }

    /// The unit direction from the target to the camera.
    fileprivate static func offset(yaw: Double, pitch: Double) -> SIMD3<Double> {
        SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
    }

    /// The numbers of one fit: the lens, the shape of the view and the corners to keep in view.
    private struct Fit {
        let aspect: Double
        let fitHeight: Double
        let tanHalf = tan(LudoSceneStyle.cameraFieldOfViewDegrees / 2 * .pi / 180)
        let corners = Fit.boardPoints()
        let props = Fit.propPoints()

        private static let nearestDistance = 3.0
        private static let farthestDistance = 400.0
        private static let targetRange = 12.0

        /// The corners of the slab at the floor and at the height of the tallest thing on it.
        /// They must fit the view both ways.
        private static func boardPoints() -> [SIMD3<Double>] {
            let half = Double(LudoWorld.halfSlab)
            var points: [SIMD3<Double>] = []
            for height in [0, LudoSceneStyle.cameraExtraHeight] {
                for sign in [(-1.0, -1.0), (-1.0, 1.0), (1.0, -1.0), (1.0, 1.0)] {
                    points.append(SIMD3(sign.0 * half, height, sign.1 * half))
                }
            }
            return points
        }

        /// The props round the board from their foot to their top. They must stay clear of
        /// the rows above and below, but may run off the sides.
        private static func propPoints() -> [SIMD3<Double>] {
            let reach = Double(LudoSceneStyle.framedPropReach)
            return LudoSceneStyle.framedProps.flatMap { prop in
                let foot = SIMD2<Double>(Double(prop.spot.x), Double(prop.spot.y))
                return [
                    SIMD3(foot.x, 0, foot.y - reach),
                    SIMD3(foot.x, 0, foot.y + reach),
                    SIMD3(foot.x, Double(prop.height), foot.y)
                ]
            }
        }

        func cameraPosition(distance: Double, targetZ: Double) -> SIMD3<Double> {
            let direction = LudoCameraFit.offset(yaw: LudoCameraPose.defaultYaw, pitch: LudoCameraPose.defaultPitch)
            return SIMD3(0, 0, targetZ) + direction * distance
        }

        /// How far outside the allowed area the points reach, 1 or less when they fit.
        func extents(distance: Double, targetZ: Double) -> (largest: Double, centerY: Double) {
            let camera = cameraPosition(distance: distance, targetZ: targetZ)
            let target = SIMD3<Double>(0, 0, targetZ)
            var largest = 0.0
            var lowest = Double.infinity
            var highest = -Double.infinity
            let height = (1 - LudoSceneStyle.cameraMargin) * fitHeight
            for (index, point) in (corners + props).enumerated() {
                guard let ndc = LudoCameraRig.normalized(
                    point, camera: camera, target: target, tanHalf: tanHalf, aspect: aspect
                ) else { return (.infinity, 0) }
                let isBoard = index < corners.count
                largest = max(largest, abs(ndc.y) / height, isBoard ? abs(ndc.x) : 0)
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
    static func fitting(aspect: Double, fitHeight: Double = 1) -> LudoCameraRig {
        LudoCameraFit.make(aspect: aspect, fitHeight: fitHeight).rig(for: .home)
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

    /// The point at `height` above the board's surface that shows at `point` in the
    /// view, from 0 to 1 across and down, as (x, z). Nil when that spot of the view shows sky.
    func boardPoint(at point: CGPoint, height: Double = 0) -> SIMD2<Double>? {
        let tanHalf = tan(Double(fieldOfViewDegrees) / 2 * .pi / 180)
        let camera = SIMD3<Double>(Double(position.x), Double(position.y), Double(position.z))
        let focus = SIMD3<Double>(Double(target.x), Double(target.y), Double(target.z))
        let axes = Axes(camera: camera, target: focus)
        let ray = axes.forward
            + axes.right * ((Double(point.x) * 2 - 1) * tanHalf * aspect)
            + axes.up * ((1 - Double(point.y) * 2) * tanHalf)
        guard ray.y < -0.0001, camera.y > height else { return nil }
        let hit = camera + ray * ((height - camera.y) / ray.y)
        return SIMD2(hit.x, hit.z)
    }

    /// The camera's forward, right and up directions when it looks from `camera` at `target`.
    private struct Axes {
        let forward: SIMD3<Double>
        let right: SIMD3<Double>
        let up: SIMD3<Double>

        init(camera: SIMD3<Double>, target: SIMD3<Double>) {
            forward = simd_normalize(target - camera)
            right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
            up = simd_cross(right, forward)
        }
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
        let axes = Axes(camera: camera, target: target)
        let offset = point - camera
        let depth = simd_dot(offset, axes.forward)
        guard depth > 0.01 else { return nil }
        return SIMD2(
            simd_dot(offset, axes.right) / depth / (tanHalf * aspect),
            simd_dot(offset, axes.up) / depth / tanHalf
        )
    }
}
