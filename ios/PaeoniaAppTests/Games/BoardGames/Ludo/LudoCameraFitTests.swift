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

    /// Past the far distance the scene shows plain background in a flat band, so the
    /// table must reach its full dark inside it at the farthest zoom.
    @Test func theFarthestZoomDrawsTheTableUntilItFadesDark() {
        let fit = LudoCameraFit.make(aspect: 0.44, fitHeight: 0.68)
        let radius = Double(LudoSceneStyle.roomDarkRadius)
        let rig = fit.rig(for: LudoCameraPose(zoom: LudoSceneStyle.zoomRange.upperBound))
        let camera = SIMD3<Double>(rig.position)
        let forward = simd_normalize(SIMD3<Double>(rig.target) - camera)
        let deepest = stride(from: 0.0, to: 2 * .pi, by: 0.05).map { angle in
            simd_dot(SIMD3(radius * cos(angle), 0, radius * sin(angle)) - camera, forward)
        }.max() ?? 0
        #expect(deepest < Double(LudoSceneStyle.cameraFar))
    }
}
