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
}
