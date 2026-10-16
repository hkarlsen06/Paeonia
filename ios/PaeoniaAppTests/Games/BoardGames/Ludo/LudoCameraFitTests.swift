import Foundation
import simd
import Testing
@testable import PaeoniaApp

struct LudoCameraFitTests {
    @Test func aViewThatReachesPastItsSlotFitsTheBoardInTheMiddleBand() {
        for aspect in [0.5, 1.0, LudoSceneStyle.viewAspect] {
            let rig = LudoCameraRig.fitting(aspect: aspect, fitHeight: 0.5)
            let half = LudoWorld.halfSlab
            for corner in [SIMD3(-half, 0, -half), SIMD3(-half, 0, half), SIMD3(half, 0, -half), SIMD3(half, 0, half)] {
                #expect((0.24...0.76).contains(Double(rig.project(corner)?.y ?? -1)), "aspect \(aspect)")
            }
        }
    }

    /// The floor fills the whole view at the farthest zoom, however the board is turned:
    /// every corner of the view lands on it, inside its edges and nearer than the far
    /// distance, so the plain background never shows.
    @Test func theFloorFillsTheViewAtTheFarthestZoom() {
        let fit = LudoCameraFit.make(aspect: 0.44, fitHeight: 0.68)
        let floor = -Double(LudoSceneStyle.slabThickness + LudoSceneStyle.tableHeight)
        let half = Double(LudoSceneStyle.floorSize) / 2
        for yaw in stride(from: 0.0, to: 2 * .pi, by: 0.3) {
            let rig = fit.rig(for: LudoCameraPose(yaw: yaw, zoom: LudoSceneStyle.zoomRange.upperBound))
            let camera = SIMD3<Double>(rig.position)
            let forward = simd_normalize(SIMD3<Double>(rig.target) - camera)
            for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
                guard let hit = rig.boardPoint(at: corner, height: floor) else {
                    Issue.record("the view shows sky at yaw \(yaw)")
                    continue
                }
                #expect(abs(hit.x) < half && abs(hit.y) < half, "yaw \(yaw)")
                let depth = simd_dot(SIMD3(hit.x, floor, hit.y) - camera, forward)
                #expect(depth < Double(LudoSceneStyle.cameraFar), "yaw \(yaw)")
            }
        }
    }
}
