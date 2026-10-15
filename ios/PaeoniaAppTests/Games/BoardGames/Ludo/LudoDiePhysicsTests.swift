import Foundation
import simd
import Testing
@testable import PaeoniaApp

struct LudoDiePhysicsTests {
    private let tray = LudoDieTray.near(waitingSlots: [0, 1])

    /// A hard flick, a slow one and two taps.
    private var tosses: [LudoToss] {
        let rest = LudoWorld.dieRestPosition(isNear: true)
        let held = rest + SIMD3(0, LudoSceneStyle.dieHoldLift, 0)
        let turn = LudoDieFaces.orientation(showing: 3)
        return [
            .thrown(from: held, orientation: turn, floorVelocity: SIMD2(-12, -6), fallbackDirection: SIMD2(0, -1)),
            .thrown(from: held, orientation: turn, floorVelocity: .zero, fallbackDirection: SIMD2(0, -1)),
            .tap(seed: 1),
            .tap(seed: 99)
        ]
    }

    @Test func everyThrowLandsFlatOnTheRolledFaceInsideTheYard() {
        let halfSize = LudoSceneStyle.dieSize / 2
        for toss in tosses {
            for value in 1...6 {
                let flight = LudoDiePhysics.flight(for: toss, showing: value, in: tray)
                let end = flight.pose(at: flight.duration)

                #expect(flight.face == value)
                #expect(abs(end.position.y - (tray.floor + halfSize)) < 0.001)
                #expect(flight.duration <= LudoSceneStyle.tossSettleLimit + LudoSceneStyle.tossSetDownTime + 0.02)
                // The face on top points straight up.
                let up = end.orientation.act(LudoDieFaces.face(value).normal)
                #expect(simd_dot(up, SIMD3(0, 1, 0)) > 0.9999)
                for position in flight.positions {
                    #expect(position.x > tray.minimum.x && position.x < tray.maximum.x)
                    #expect(position.z > tray.minimum.y && position.z < tray.maximum.y)
                }
                // It does not come to rest in a waiting pawn.
                for pawn in tray.pawns {
                    #expect(simd_distance(SIMD2(end.position.x, end.position.z), pawn) > halfSize + 0.4)
                }
            }
        }
    }

    /// A die let go flies on with its throw until its roll arrives, so that flight
    /// has to match the start of the simulated one.
    @Test func aDieLetGoFliesTheWayTheSimulationStarts() {
        for toss in tosses {
            let flight = LudoDiePhysics.simulate(toss, in: tray).flight
            let pose = toss.pose(after: Float(2 * LudoDieFlight.frameTime))
            #expect(simd_distance(pose.position, flight.positions[2]) < 0.02)
        }
    }

    @Test func theSameThrowFliesTheSameWay() {
        for toss in tosses {
            let first = LudoDiePhysics.flight(for: toss, showing: 4, in: tray)
            let second = LudoDiePhysics.flight(for: toss, showing: 4, in: tray)
            #expect(first == second)
        }
    }

    @Test func aThrowSurvivesTheTripToThePartnersPhone() throws {
        let toss = LudoToss.tap(seed: 5)
        let roll = LudoSavedRoll(position: position(moveCount: 3), die: 2)
        let data = try JSONEncoder().encode(LudoLiveMessage(roll: roll, toss: toss))
        let message = try JSONDecoder().decode(LudoLiveMessage.self, from: data)
        #expect(message.toss == toss)
    }

    @Test func aTapThrowsTheSameWayOnBothPhones() {
        let seed = position(moveCount: 4).tossSeed
        #expect(LudoToss.tap(seed: seed) == LudoToss.tap(seed: position(moveCount: 4).tossSeed))
        #expect(position(moveCount: 4).tossSeed != position(moveCount: 5).tossSeed)
    }

    @MainActor
    @Test func theFarYardIsTheNearYardTurnedHalfACircle() {
        let near = LudoWorld.dieRestPosition(isNear: true)
        let turned = LudoStage.worldPose((near, simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))), isNear: false)
        #expect(simd_distance(turned.position, LudoWorld.dieRestPosition(isNear: false)) < 0.0001)
    }

    private static let gameID = UUID()

    private func position(moveCount: Int) -> LudoPosition {
        LudoPosition(gameID: Self.gameID, gameNumber: 1, moveCount: moveCount)
    }
}
