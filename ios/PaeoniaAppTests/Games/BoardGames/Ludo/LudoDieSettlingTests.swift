import Testing
import simd
@testable import PaeoniaApp

struct LudoDieSettlingTests {
    private let rest = SIMD3<Float>(0, 0.65, 0)
    private let flat = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    @Test func aNearlyStillTailSettlesWithoutWaitingForEveryFrame() {
        let tail = (0..<30).map { frame in rest + SIMD3<Float>(0.04 * Float(29 - frame) / 29, 0, 0) }
        var flight = LudoDieFlight(
            positions: [SIMD3(0, 2, 0)] + tail,
            orientations: Array(repeating: flat, count: 31),
            knocks: [0]
        )
        LudoDiePhysics.setDown(&flight, floor: 0)
        #expect(flight.duration < 0.3)
        #expect(flight.positions.first == SIMD3(0, 2, 0))
        #expect(flight.positions.last == rest)
        #expect(flight.face == 1)
        #expect(flight.knocks == [0])
    }

    @Test func aQuietMomentBeforeAnotherBounceStillPlays() {
        var positions = Array(repeating: rest, count: 30)
        positions[20] += SIMD3(0, 0.5, 0)
        var flight = LudoDieFlight(
            positions: positions, orientations: Array(repeating: flat, count: 30), knocks: [0.33]
        )
        LudoDiePhysics.setDown(&flight, floor: 0)
        #expect(flight.positions[20] == positions[20])
        #expect(flight.knocks == [0.33])
        #expect(flight.positions.last == rest)
    }

    @Test func aLateChangeOfFaceStillPlays() {
        let turned = LudoDieFaces.orientation(showing: 6)
        var orientations = Array(repeating: flat, count: 30)
        for index in 20..<30 { orientations[index] = turned }
        var flight = LudoDieFlight(
            positions: Array(repeating: rest, count: 30), orientations: orientations, knocks: []
        )
        LudoDiePhysics.setDown(&flight, floor: 0)
        #expect(flight.orientations[19] == flat)
        #expect(flight.face == 6)
    }

    @Test func simulatedThrowsStillLandOnTheRequestedFace() {
        let tray = LudoDieTray.near(waitingSlots: [0, 1])
        for seed in UInt64(1)...8 {
            for face in 1...6 {
                let toss = LudoToss.tap(seed: seed)
                let flight = LudoDiePhysics.flight(for: toss, showing: face, in: tray)
                #expect(flight.face == face)
                #expect(flight.positions.last?.y == LudoSceneStyle.dieSize / 2)
                #expect(flight.knocks.allSatisfy { $0 <= flight.duration })
            }
        }
    }
}
