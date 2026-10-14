import CoreGraphics
import Foundation
import simd
import Testing
@testable import PaeoniaApp

struct LudoBoardGeometryTests {
    private let viewers: [BoardPlayer] = [.one, .two]
    private let players: [BoardPlayer] = [.one, .two]

    private struct Key: Hashable {
        let row: Int
        let column: Int
    }

    private func key(_ point: LudoGridPoint) -> Key {
        Key(row: Int((point.row * 100).rounded()), column: Int((point.column * 100).rounded()))
    }

    /// Every square a pawn can stand on, with the lane that tells two pawns at home apart.
    private func allSquares() -> [(square: LudoSquare, lane: Int)] {
        var squares: [(LudoSquare, Int)] = (0..<LudoBoard.trackLength).map { (.track($0), 0) }
        for player in players {
            for step in 1...5 {
                squares.append((.homeColumn(player, step: step), 0))
            }
            for slot in 0..<LudoBoard.pawnsPerPlayer {
                squares.append((.base(player, slot: slot), 0))
                squares.append((.home(player), slot))
            }
        }
        return squares.map { (square: $0.0, lane: $0.1) }
    }

    private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.001) -> Bool {
        abs(first - second) < tolerance
    }

    // MARK: Squares

    @Test func everySquareHasItsOwnPlaceOnTheGrid() {
        for viewer in viewers {
            let squares = allSquares()
            let points = squares.map { LudoBoardGeometry.point(of: $0.square, homeLane: $0.lane, viewer: viewer) }
            let keys = Set(points.map { key($0) })

            #expect(squares.count == 70)
            #expect(keys.count == squares.count)
        }
    }

    @Test func everyPointIsOnTheBoard() {
        for viewer in viewers {
            for entry in allSquares() {
                let point = LudoBoardGeometry.point(of: entry.square, homeLane: entry.lane, viewer: viewer)

                #expect((0.0...14.0).contains(point.row))
                #expect((0.0...14.0).contains(point.column))
            }
        }
    }

    @Test func trackSquaresAreNeighborsInWalkingOrder() {
        for viewer in viewers {
            for index in 0..<LudoBoard.trackLength {
                let from = LudoBoardGeometry.point(of: .track(index), viewer: viewer)
                let to = LudoBoardGeometry.point(of: .track((index + 1) % LudoBoard.trackLength), viewer: viewer)
                let step = max(abs(from.row - to.row), abs(from.column - to.column))

                #expect(isClose(step, 1), "square \(index) to the next")
            }
        }
    }

    @Test func theTrackRunsClockwiseOnScreen() {
        for viewer in viewers {
            let points = (0..<LudoBoard.trackLength).map { LudoBoardGeometry.point(of: .track($0), viewer: viewer) }
            // Shoelace sum with rows pointing down: positive means clockwise.
            var area = 0.0
            for index in points.indices {
                let current = points[index]
                let next = points[(index + 1) % points.count]
                area += current.column * next.row - next.column * current.row
            }

            #expect(area > 0)
        }
    }

    @Test func playerTwoStartsOppositePlayerOne() {
        for viewer in viewers {
            let one = LudoBoardGeometry.point(of: .track(LudoBoard.startSquare(of: .one)), viewer: viewer)
            let two = LudoBoardGeometry.point(of: .track(LudoBoard.startSquare(of: .two)), viewer: viewer)

            #expect(isClose(one.row + two.row, 14))
            #expect(isClose(one.column + two.column, 14))
        }
    }

    @Test func eachCornerHasItsStartSquareNextToItsYard() {
        for viewer in viewers {
            for player in players {
                let start = LudoBoardGeometry.point(
                    of: .track(LudoBoard.startSquare(of: player)),
                    viewer: viewer
                )
                let slot = LudoBoardGeometry.point(of: .base(player, slot: 0), viewer: viewer)

                #expect(start.distance(to: slot) < 5.5)
            }
        }
    }

    // MARK: Home column

    @Test func theHomeColumnLeadsFromTheLastTrackSquareToTheCenter() {
        for viewer in viewers {
            for player in players {
                let lastTrack = LudoBoard.trackSquare(of: player, progress: LudoBoard.lastTrackProgress) ?? -1
                var previous = LudoBoardGeometry.point(of: .track(lastTrack), viewer: viewer)
                var distances: [Double] = []
                let middle = LudoGridPoint(row: 7, column: 7)
                for step in 1...5 {
                    let point = LudoBoardGeometry.point(of: .homeColumn(player, step: step), viewer: viewer)

                    #expect(isClose(previous.distance(to: point), 1), "step \(step) of \(player)")
                    previous = point
                    distances.append(point.distance(to: middle))
                }
                let home = LudoBoardGeometry.point(of: .home(player), homeLane: 0, viewer: viewer)

                #expect(distances == distances.sorted(by: >))
                #expect(isClose(distances.last ?? 0, 2))
                #expect(home.distance(to: middle) < 1.5)
                #expect(previous.distance(to: home) < 1.5)
            }
        }
    }

    @Test func aPawnNeverStepsOnTheSquareJustBeforeItsStart() {
        for player in players {
            let skipped = (LudoBoard.startSquare(of: player) + LudoBoard.trackLength - 1) % LudoBoard.trackLength
            let progresses = 1...LudoBoard.lastTrackProgress
            let walked = progresses.compactMap { LudoBoard.trackSquare(of: player, progress: $0) }

            #expect(walked.count == LudoBoard.lastTrackProgress)
            #expect(!walked.contains(skipped))
        }
    }

    // MARK: Viewer

    @Test func myBaseIsAtTheBottomLeftAndMyPartnersAtTheTopRight() {
        for viewer in viewers {
            for slot in 0..<LudoBoard.pawnsPerPlayer {
                let mine = LudoBoardGeometry.point(of: .base(viewer, slot: slot), viewer: viewer)
                let theirs = LudoBoardGeometry.point(of: .base(viewer.other, slot: slot), viewer: viewer)

                #expect(mine.row > 8 && mine.column < 6)
                #expect(theirs.row < 6 && theirs.column > 8)
            }
        }
    }

    @Test func theCornerColorsKeepTheirPlaceOnScreen() {
        for viewer in viewers {
            let roles = (0..<4).map { LudoBoardGeometry.role(ofCorner: $0, viewer: viewer) }

            #expect(roles[LudoBoardGeometry.corner(of: viewer)] == .mine)
            #expect(roles[LudoBoardGeometry.corner(of: viewer.other)] == .partner)
            #expect(Set(roles.map { "\($0)" }).count == 4)
        }
    }

    // MARK: Pawns that share a square

    @Test func pawnsOnOneSquareStandSideBySide() {
        let board = LudoBoard(progress: [5, 5, 0, 0], next: .one, outcome: nil)
        let placements = LudoBoardGeometry.placements(board: board, viewer: .one)

        #expect(placements[0].point != placements[1].point)
        #expect(isClose(placements[0].point.row, placements[1].point.row))
        #expect(placements[0].scale < 1)
        #expect(placements[2].scale == 1)
    }

    @Test func pawnsAtHomeStandApartOnTheirPad() {
        let board = LudoBoard(progress: [57, 57, 0, 0], next: .one, outcome: nil)
        let placements = LudoBoardGeometry.placements(board: board, viewer: .one)

        #expect(placements[0].point != placements[1].point)
        #expect(placements[0].square == .home(.one))
    }

    // MARK: World

    @Test func columnsGoRightAndRowsGoTowardTheViewer() {
        let corner = LudoWorld.position(LudoGridPoint(row: 0, column: 0))
        let opposite = LudoWorld.position(LudoGridPoint(row: 14, column: 14))

        #expect(corner.x < opposite.x)
        #expect(corner.z < opposite.z)
        #expect(LudoWorld.position(LudoGridPoint(row: 7, column: 7)) == .zero)
    }

    // MARK: The die's resting places

    @Test func theDieRestsInTheRollersOwnYardBesideTheSlots() {
        for viewer in viewers {
            for isNear in [true, false] {
                let player = isNear ? viewer : viewer.other
                let spot = LudoBoardGeometry.dieSpot(corner: LudoBoardGeometry.corner(of: player), viewer: viewer)
                let center = LudoBoardGeometry.yardCenter(corner: LudoBoardGeometry.corner(of: player), viewer: viewer)
                let half = Double(LudoSceneStyle.dieSize) / 2

                // The whole die is inside the 6 by 6 yard.
                #expect(abs(spot.row - center.row) + half <= 3)
                #expect(abs(spot.column - center.column) + half <= 3)
                for slot in 0..<LudoBoard.pawnsPerPlayer {
                    let place = LudoBoardGeometry.point(of: .base(player, slot: slot), viewer: viewer)

                    #expect(spot.distance(to: place) > half + Double(LudoSceneStyle.yardSlotRadius))
                }
            }
        }
    }

    @Test func myDieSpotIsAtTheBottomLeftAndMyPartnersAtTheTopRight() {
        let near = LudoWorld.dieRestPosition(isNear: true)
        let far = LudoWorld.dieRestPosition(isNear: false)

        #expect(near.x < 0 && near.z > 0)
        #expect(far.x > 0 && far.z < 0)
        #expect(near.y > LudoSceneStyle.yardHeight)
        // The same on screen whoever looks: the near spot is in my yard.
        for viewer in viewers {
            let mine = LudoBoardGeometry.dieSpot(corner: LudoBoardGeometry.corner(of: viewer), viewer: viewer)
            let position = LudoWorld.position(mine)

            #expect(isNearlyEqual(position.x, near.x) && isNearlyEqual(position.z, near.z))
        }
    }

    @Test func theSlabEndsJustPastTheGrid() {
        #expect(LudoWorld.halfSlab == LudoWorld.halfBoard + LudoSceneStyle.slabMargin)
        #expect(LudoSceneStyle.slabMargin <= 0.5)
    }

    private func isNearlyEqual(_ first: Float, _ second: Float) -> Bool {
        abs(first - second) < 0.001
    }
}

struct LudoSceneMathTests {
    private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.001) -> Bool {
        abs(first - second) < tolerance
    }

    // MARK: Camera

    @Test func theBoardFillsTheWidthAndFitsTheHeightOfEveryShapeOfView() {
        for aspect in [0.5, 0.7, 1.0, LudoSceneStyle.viewAspect, 2.0] {
            let rig = LudoCameraRig.fitting(aspect: aspect)
            let half = LudoWorld.halfBoard
            let corners: [SIMD3<Float>] = [
                SIMD3(-half, 0, -half), SIMD3(-half, 0, half), SIMD3(half, 0, -half), SIMD3(half, 0, half)
            ]
            let points = corners.compactMap { rig.project($0) }

            // The near corners may run past each side by half the overshoot.
            let past = LudoSceneStyle.cameraOvershoot / 2 + 0.01
            #expect(points.count == 4)
            for point in points {
                #expect((-past...(1 + past)).contains(Double(point.x)), "aspect \(aspect)")
                #expect((0.0...1.0).contains(Double(point.y)), "aspect \(aspect)")
            }
            let left = points.map(\.x).min() ?? 1
            let right = points.map(\.x).max() ?? 0
            let middle = rig.project(.zero)

            if aspect <= 1.0 {
                // Tall views are filled sideways.
                #expect(right - left > 0.9, "aspect \(aspect)")
            }
            #expect(abs(Double(middle?.x ?? 0) - 0.5) < 0.001)
            #expect(abs(Double(middle?.y ?? 0) - 0.5) < 0.2)
        }
    }

    @Test func theOrbitKeepsThePitchAndZoomInsideTheirLimits() {
        let steep = LudoCameraPose(yaw: 8, pitch: 3, zoom: 9).clamped
        let flat = LudoCameraPose(yaw: -8, pitch: -1, zoom: 0.01).clamped

        #expect(isClose(steep.pitch * 180 / .pi, LudoSceneStyle.orbitPitchRangeDegrees.upperBound))
        #expect(isClose(flat.pitch * 180 / .pi, LudoSceneStyle.orbitPitchRangeDegrees.lowerBound))
        #expect(steep.zoom == LudoSceneStyle.zoomRange.upperBound)
        #expect(flat.zoom == LudoSceneStyle.zoomRange.lowerBound)
        #expect(abs(steep.yaw) <= .pi && abs(flat.yaw) <= .pi)
        #expect(LudoSceneStyle.orbitPitchRangeDegrees.contains(LudoSceneStyle.cameraPitchDegrees))
    }

    @Test func zoomingMovesTheCameraAlongItsView() {
        let fit = LudoCameraFit.make(aspect: 0.7)
        let near = fit.rig(for: LudoCameraPose(yaw: 0, pitch: LudoCameraPose.defaultPitch, zoom: 0.6))
        let far = fit.rig(for: LudoCameraPose(yaw: 0, pitch: LudoCameraPose.defaultPitch, zoom: 1.3))

        #expect(simd_distance(near.position, near.target) < simd_distance(far.position, far.target))
        #expect(near.target == far.target)
    }

    @Test func orbitingKeepsTheBoardCenterInTheMiddleOfTheView() {
        let fit = LudoCameraFit.make(aspect: 0.7)
        let turned = fit.rig(for: LudoCameraPose(yaw: 2.2, pitch: 0.9, zoom: 1))
        let middle = turned.project(SIMD3(0, 0, Float(fit.targetZ)))

        #expect(abs(Double(middle?.x ?? 0) - 0.5) < 0.001)
        #expect(abs(Double(middle?.y ?? 0) - 0.5) < 0.001)
    }

    @Test func theResetGlideTakesTheShortWayRound() {
        let start = LudoCameraPose(yaw: 3.0, pitch: 0.7, zoom: 1.2)
        let halfway = start.blended(to: .home, amount: 0.5)
        let nearlyThere = LudoCameraPose(yaw: -3.0, pitch: 0.7, zoom: 1).blended(to: .home, amount: 0.5)

        #expect(isClose(halfway.yaw, 1.5))
        #expect(isClose(nearlyThere.yaw, -1.5))
        #expect(start.blended(to: .home, amount: 1).zoom == 1)
    }

    @Test func theCameraLooksDownAtTheConfiguredAngle() {
        let rig = LudoCameraRig.fitting(aspect: 1)
        let offset = rig.position - rig.target
        let pitch = atan2(Double(offset.y), Double(offset.z)) * 180 / .pi

        #expect(isClose(pitch, LudoSceneStyle.cameraPitchDegrees, tolerance: 0.01))
    }

    // MARK: Die

    @Test func everyFaceCanBeTurnedToTheTop() {
        for value in 1...6 {
            let up = LudoDieFaces.orientation(showing: value).act(LudoDieFaces.face(value).normal)

            #expect(simd_distance(up, SIMD3(0, 1, 0)) < 0.0001, "face \(value)")
        }
    }

    @Test func oppositeFacesAddUpToSeven() {
        for value in 1...6 {
            let sum = LudoDieFaces.face(value).normal + LudoDieFaces.face(7 - value).normal

            #expect(sum == .zero)
            #expect(LudoDieFaces.pips(value).count == value)
        }
    }

    @Test func everyFacePointsItsHeartsTowardTheViewerWhenOnTop() {
        for value in 1...6 {
            let face = LudoDieFaces.face(value)
            let lifted = LudoDieFaces.lift(value)

            #expect(simd_distance(lifted.act(face.down), SIMD3(0, 0, 1)) < 0.0001, "face \(value)")
            #expect(simd_distance(lifted.act(face.across), SIMD3(1, 0, 0)) < 0.0001, "face \(value)")
        }
    }

    @Test func theTumbleEndsExactlyOnTheRolledFace() {
        let start = LudoDieFaces.orientation(showing: 4)
        for value in 1...6 {
            let final = LudoDieFaces.orientation(showing: value)
            let end = SIMD3<Float>(1, 0.6, 2)
            let begin = SIMD3<Float>(-3, 0.6, -2)

            #expect(LudoMotion.tumblePosition(from: begin, to: end, progress: 1) == end)
            #expect(LudoMotion.tumbleOrientation(from: start, to: final, progress: 1) == final)
            let before = LudoMotion.tumbleOrientation(from: start, to: final, progress: 0)
            #expect(abs(simd_dot(before, start)) > 0.9999)
        }
    }

    @Test func theDieTouchesDownAtTheEndOfEachBounce() {
        let landings = LudoMotion.tumbleLandings()

        #expect(landings.count == LudoSceneStyle.bounceShares.count)
        #expect(isClose(landings.last ?? 0, 1))
        for landing in landings {
            #expect(LudoMotion.tumbleHeight(progress: landing - 0.0001) < 0.01)
        }
        #expect(LudoMotion.tumbleHeight(progress: landings[0] / 2) > 0.5)
    }

    // MARK: Motion

    @Test func aPawnHopsThroughEveryPointAndStopsOnTheLast() {
        let points = [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1)]
        let hop = LudoSceneStyle.hopDuration

        #expect(LudoMotion.hops(through: points, elapsed: 0, hopDuration: hop, arc: 0.4) == points[0])
        #expect(LudoMotion.hops(through: points, elapsed: hop, hopDuration: hop, arc: 0.4) == points[1])
        #expect(LudoMotion.hops(through: points, elapsed: 2 * hop, hopDuration: hop, arc: 0.4) == points[2])
        #expect(LudoMotion.hops(through: points, elapsed: 5, hopDuration: hop, arc: 0.4) == points[2])
        #expect(LudoMotion.hops(through: points, elapsed: hop / 2, hopDuration: hop, arc: 0.4).y > 0.3)
    }

    @Test func aPawnSentHomeLandsOnItsBase() {
        let start = SIMD3<Float>(3, 0.12, -2)
        let base = SIMD3<Float>(-4, 0.17, 4)
        let duration = LudoSceneStyle.sendHomeDuration

        #expect(LudoMotion.sendHome(from: start, to: base, elapsed: 0, duration: duration) == start)
        #expect(LudoMotion.sendHome(from: start, to: base, elapsed: duration, duration: duration) == base)
        #expect(LudoMotion.sendHome(from: start, to: base, elapsed: duration * 0.4, duration: duration).y > 1)
    }

    @Test func aShakeSettlesWhereItStarted() {
        #expect(LudoMotion.shake(progress: 0) == 0)
        #expect(abs(LudoMotion.shake(progress: 1)) < 0.0001)
    }

    // MARK: Shapes

    @Test func theTurnedShapesAreWellFormed() {
        let disc = LudoMeshGeometry.disc(radius: 0.3, segments: 24, flipsVertically: false)
        for data in [LudoMeshGeometry.pawn(), LudoMeshGeometry.domeHalf(), LudoMeshGeometry.heart(), disc] {
            #expect(!data.positions.isEmpty)
            #expect(data.positions.count == data.normals.count)
            #expect(data.positions.count == data.uvs.count)
            #expect(data.indices.count % 3 == 0)
            #expect(data.indices.allSatisfy { Int($0) < data.positions.count })
            #expect(data.normals.allSatisfy { abs(simd_length($0) - 1) < 0.001 })
        }
    }

    @Test func thePawnStandsOnTheFloorAndEndsInAFlatTop() {
        let data = LudoMeshGeometry.pawn()
        let lowest = data.positions.map(\.y).min() ?? 1
        let highest = data.positions.map(\.y).max() ?? 0

        #expect(abs(lowest) < 0.0001)
        #expect(abs(highest - LudoSceneStyle.pawnHeight) < 0.0001)
    }

    @Test func theMarkDiscShowsTheWholePicture() {
        let disc = LudoMeshGeometry.disc(radius: 0.25, segments: 24, flipsVertically: false)
        let us = disc.uvs.map(\.x)
        let vs = disc.uvs.map(\.y)

        #expect(abs((us.min() ?? 1) - 0) < 0.001)
        #expect(abs((us.max() ?? 0) - 1) < 0.001)
        #expect(abs((vs.min() ?? 1) - 0) < 0.001)
        #expect(abs((vs.max() ?? 0) - 1) < 0.001)
    }
}

extension LudoSceneMathTests {
    @Test func aHeartPipIsSmallRaisedAndPointsTowardPlusZ() {
        let heart = LudoMeshGeometry.heart()
        let xs = heart.positions.map(\.x)
        let ys = heart.positions.map(\.y)
        let tip = heart.positions.max { $0.z < $1.z } ?? .zero

        #expect(isClose(Double((xs.max() ?? 0) - (xs.min() ?? 0)), Double(LudoSceneStyle.pipWidth), tolerance: 0.002))
        #expect(isClose(Double(ys.max() ?? 0), Double(LudoSceneStyle.pipHeight), tolerance: 0.0001))
        #expect(abs(ys.min() ?? 1) < 0.0001)
        #expect(abs(tip.x) < 0.01)
    }

    @Test func aDomeHalfCoversOneSideOfTheSeam() {
        let dome = LudoMeshGeometry.domeHalf()
        let radius = dome.positions.map { ($0.x * $0.x + $0.z * $0.z).squareRoot() }.max() ?? 0

        #expect(dome.positions.allSatisfy { $0.z > -0.0001 })
        #expect(isClose(Double(radius), Double(LudoSceneStyle.domeDiameter / 2), tolerance: 0.001))
        let top = Double(dome.positions.map(\.y).max() ?? 0)

        #expect(isClose(top, Double(LudoSceneStyle.domeHeight), tolerance: 0.0001))
    }
}
