import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

struct ConnectFourBoardGeometryTests {
    /// 366 points wide gives a 50 point cell, an 8 point frame and 40 point holes.
    private let geometry = ConnectFourBoardGeometry(width: 366)

    private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.001) -> Bool {
        abs(first - second) < tolerance
    }

    private func index(_ row: Int, _ column: Int) -> Int {
        row * ConnectFourBoard.columns + column
    }

    // MARK: Layout

    @Test func theLaneAndTheBoardTogetherFillASquare() {
        for width in [280.0, 366, 430, 560, 640] {
            let sized = ConnectFourBoardGeometry(width: width)

            #expect(isClose(sized.totalHeight, sized.width))
        }
        #expect(isClose(geometry.cell, 50))
        #expect(isClose(geometry.holeDiameter, 40))
    }

    @Test func theBoardCapsAtFiveHundredSixtyPointsUnlessTheScreenAsksForMore() {
        #expect(ConnectFourBoardGeometry.defaultMaxWidth == 560)
        #expect(ConnectFourBoardGeometry(width: -5).width == 0)
    }

    @Test func cellsAreNumberedFromTheTopLeftAndRowZeroIsOnTop() {
        let topLeft = geometry.cellCenter(index: 0)
        let bottomRight = geometry.cellCenter(index: 41)
        let belowTopLeft = geometry.cellCenter(index: 7)

        #expect(topLeft.x < bottomRight.x)
        #expect(topLeft.y < bottomRight.y)
        #expect(belowTopLeft.x == topLeft.x)
        #expect(isClose(belowTopLeft.y - topLeft.y, geometry.cell))
        #expect(geometry.cellCenter(index: index(2, 5)) == geometry.cellCenter(row: 2, column: 5))
    }

    @Test func theTopRowSitsBelowTheLane() {
        let top = geometry.cellCenter(row: 0, column: 0)
        let bottom = geometry.cellCenter(row: 5, column: 0)

        #expect(top.y > geometry.laneHeight)
        #expect(isClose(bottom.y + geometry.cell / 2 + geometry.inset, geometry.totalHeight))
    }

    @Test func holesFitInsideTheFaceAndDoNotTouch() {
        let face = CGRect(x: 0, y: 0, width: geometry.width, height: geometry.boardHeight)
        for row in 0..<ConnectFourBoardGeometry.rows {
            for column in 0..<ConnectFourBoardGeometry.columns {
                let hole = geometry.holeRect(row: row, column: column)
                #expect(face.contains(hole))
                #expect(hole.width < geometry.cell)
            }
        }
        #expect(geometry.discDiameter > geometry.holeDiameter)
    }

    @Test func theHoverDiscSitsInTheMiddleOfTheLaneAboveItsColumn() {
        let hover = geometry.hoverCenter(column: 4)

        #expect(isClose(hover.y, geometry.laneHeight / 2))
        #expect(hover.x == geometry.cellCenter(row: 0, column: 4).x)
    }

    // MARK: Touch

    @Test func aFingerPicksTheColumnUnderIt() {
        for column in 0..<ConnectFourBoardGeometry.columns {
            #expect(geometry.column(forX: geometry.columnCenterX(column)) == column)
        }
        #expect(geometry.column(forX: geometry.inset + geometry.cell * 2.99) == 2)
        #expect(geometry.column(forX: geometry.inset + geometry.cell * 3.01) == 3)
    }

    @Test func aFingerBesideTheBoardPicksTheFirstOrLastColumn() {
        #expect(geometry.column(forX: -40) == 0)
        #expect(geometry.column(forX: 3) == 0)
        #expect(geometry.column(forX: 10_000) == 6)
        #expect(ConnectFourBoardGeometry(width: 0).column(forX: 12) == 0)
    }

    // MARK: Winning runs

    @Test func aHorizontalRunIsOneRunInOrder() {
        let line = [index(5, 0), index(5, 1), index(5, 2), index(5, 3)]

        #expect(ConnectFourBoardGeometry.runs(in: line) == [line])
    }

    @Test func verticalAndBothDiagonalRunsAreFound() {
        let vertical = [index(2, 3), index(3, 3), index(4, 3), index(5, 3)]
        let down = [index(2, 0), index(3, 1), index(4, 2), index(5, 3)]
        let up = [index(2, 3), index(3, 2), index(4, 1), index(5, 0)]

        #expect(ConnectFourBoardGeometry.runs(in: vertical) == [vertical])
        #expect(ConnectFourBoardGeometry.runs(in: down) == [down])
        #expect(ConnectFourBoardGeometry.runs(in: up) == [up])
    }

    @Test func aRunOfFiveIsOneLineThroughAllFive() {
        let line = (0..<5).map { index(4, $0) }

        #expect(ConnectFourBoardGeometry.runs(in: line) == [line])
    }

    @Test func twoRunsThroughOneDiscAreTwoLines() {
        let horizontal = [index(5, 0), index(5, 1), index(5, 2), index(5, 3)]
        let vertical = [index(2, 0), index(3, 0), index(4, 0), index(5, 0)]
        let union = Set(horizontal + vertical).sorted()

        let runs = ConnectFourBoardGeometry.runs(in: union)

        #expect(runs.count == 2)
        #expect(runs.contains(horizontal))
        #expect(runs.contains(vertical))
    }

    @Test func aDrawHasNoRuns() {
        #expect(ConnectFourBoardGeometry.runs(in: []).isEmpty)
    }

    @Test func theBloomStartsAtTheMiddleOfTheWinningLine() {
        let line = [index(5, 0), index(5, 1), index(5, 2), index(5, 3)]
        let first = geometry.cellCenter(index: line[0])
        let last = geometry.cellCenter(index: line[3])

        let middle = geometry.middle(of: line)

        #expect(isClose(middle.x, (first.x + last.x) / 2))
        #expect(isClose(middle.y, first.y))
    }

    // MARK: Board helpers

    @Test func theTopDiscIsTheOneDroppedLast() throws {
        let board = try #require(ConnectFourBoard.replay([3, 3, 2]))

        #expect(board.topDiscIndex(column: 3) == index(4, 3))
        #expect(board.topDiscIndex(column: 2) == index(5, 2))
        #expect(board.topDiscIndex(column: 0) == nil)
        #expect(board.topDiscIndex(column: 9) == nil)
        #expect(board.discCount(inColumn: 3) == 2)
        #expect(board.discCount(inColumn: 0) == 0)
    }

    @Test func aFullColumnsTopDiscIsOnTheTopRow() throws {
        let board = try #require(ConnectFourBoard.replay([0, 0, 0, 0, 0, 0]))

        #expect(board.topDiscIndex(column: 0) == index(0, 0))
        #expect(board.discCount(inColumn: 0) == 6)
    }

    // MARK: Drop motion

    @Test func theDistanceToARowGrowsByOneCellPerRow() {
        let first = ConnectFourBoardGeometry.dropDistance(toRow: 0)

        #expect(isClose(first, 1.16))
        #expect(isClose(ConnectFourBoardGeometry.dropDistance(toRow: 5), first + 5))
    }

    @Test func aFallTakesBetweenAQuarterAndHalfASecondAndLongerDropsTakeLonger() {
        let short = ConnectFourDropMotion(distance: ConnectFourBoardGeometry.dropDistance(toRow: 0))
        let middle = ConnectFourDropMotion(distance: 3)
        let long = ConnectFourDropMotion(distance: ConnectFourBoardGeometry.dropDistance(toRow: 5))
        let beyond = ConnectFourDropMotion(distance: 20)

        #expect(short.fallDuration == ConnectFourDropMotion.shortestFall)
        #expect(short.fallDuration < middle.fallDuration)
        #expect(middle.fallDuration < long.fallDuration)
        #expect(long.fallDuration <= ConnectFourDropMotion.longestFall)
        #expect(beyond.fallDuration == ConnectFourDropMotion.longestFall)
    }

    @Test func aDiscStartsAtTheLaneAndLandsOnItsCell() {
        let motion = ConnectFourDropMotion(distance: 4.16)

        #expect(motion.height(at: 0) == 4.16)
        #expect(motion.height(at: -1) == 4.16)
        #expect(isClose(motion.height(at: motion.landingTime), 0))
        #expect(motion.height(at: motion.totalDuration) == 0)
        #expect(motion.height(at: motion.totalDuration + 5) == 0)
    }

    @Test func aDiscSpeedsUpAsItFalls() {
        let motion = ConnectFourDropMotion(distance: 4.16)
        let quarter = motion.height(at: motion.fallDuration * 0.25)
        let half = motion.height(at: motion.fallDuration * 0.5)

        // Gravity: the first quarter of the time covers less than the second quarter does.
        #expect(motion.distance - quarter < quarter - half)
        #expect(half < quarter)
    }

    @Test func aDiscBouncesTwiceAndEachHopIsLowerThanTheLast() {
        let motion = ConnectFourDropMotion(distance: 6.16)
        let hops = motion.bounces

        #expect(hops.count == 2)
        #expect(hops[0].peak > hops[1].peak)
        #expect(hops[0].peak <= 0.3)
        #expect(isClose(motion.height(at: hops[0].start + hops[0].duration / 2), hops[0].peak))
        #expect(isClose(motion.height(at: hops[1].start + hops[1].duration / 2), hops[1].peak))
        #expect(isClose(hops[1].start, hops[0].start + hops[0].duration))
    }

    @Test func aDiscNeverGoesBelowItsCellOrAboveWhereItStarted() {
        let motion = ConnectFourDropMotion(distance: 3.16, hover: 0.25, fadeIn: 0.15)
        var time = 0.0
        while time <= motion.totalDuration + 0.1 {
            let height = motion.height(at: time)

            #expect(height >= 0)
            #expect(height <= motion.distance)
            time += 0.005
        }
    }

    @Test func aPartnersDiscHoversOverItsColumnAndFadesInBeforeItDrops() {
        let motion = ConnectFourDropMotion(
            distance: 3.16,
            hover: ConnectFourDropMotion.partnerHover,
            fadeIn: ConnectFourDropMotion.partnerFadeIn
        )

        #expect(motion.height(at: 0.1) == motion.distance)
        #expect(motion.height(at: 0.2499) == motion.distance)
        #expect(motion.height(at: 0.3) < motion.distance)
        #expect(motion.opacity(at: 0) == 0)
        #expect(isClose(motion.opacity(at: 0.075), 0.5))
        #expect(motion.opacity(at: 0.15) == 1)
        #expect(motion.opacity(at: 0.6) == 1)
        #expect(isClose(motion.landingTime, 0.25 + motion.fallDuration))
    }

    @Test func myDiscStartsFullyVisible() {
        let motion = ConnectFourDropMotion(distance: 3.16)

        #expect(motion.opacity(at: 0) == 1)
        #expect(motion.hoverDuration == 0)
    }

    @Test func reduceMotionFadesTheDiscInAtItsCellAndNeverMoves() {
        let motion = ConnectFourDropMotion.reduced(fadeIn: 0.16)

        #expect(motion.landingTime == 0)
        #expect(motion.totalDuration == 0.16)
        #expect(motion.bounces.isEmpty)
        #expect(motion.height(at: 0) == 0)
        #expect(motion.height(at: 0.1) == 0)
        #expect(motion.opacity(at: 0) == 0)
        #expect(motion.opacity(at: 0.16) == 1)
    }

    @Test func theLongestDropAndBouncesFinishInUnderOneSecond() {
        let motion = ConnectFourDropMotion(distance: 6.16)

        #expect(motion.totalDuration > motion.landingTime)
        #expect(motion.totalDuration < 1)
    }

    // MARK: Result timing

    @Test func winningCellsLightUpInOrderEightHundredthsOfASecondApart() {
        let timing = ConnectFourOutcomeTiming.self

        #expect(timing.glow(rank: 0, elapsed: -0.1) == 0)
        #expect(timing.glow(rank: 0, elapsed: 0.2) == 1)
        #expect(timing.glow(rank: 3, elapsed: 0.2) == 0)
        #expect(timing.glow(rank: 3, elapsed: 3 * 0.08 + 0.2) == 1)
        #expect(timing.glow(rank: 6, elapsed: .infinity) == 1)
    }

    @Test func aLitDiscPulsesUpToOneTwelveAndBackToOne() {
        let timing = ConnectFourOutcomeTiming.self

        #expect(timing.scale(rank: 0, elapsed: 0) == 1)
        #expect(isClose(Double(timing.scale(rank: 0, elapsed: 0.15)), 1.12))
        #expect(timing.scale(rank: 0, elapsed: 0.3) == 1)
        #expect(timing.scale(rank: 2, elapsed: 0.1) == 1)
        #expect(timing.scale(rank: 2, elapsed: .infinity) == 1)
    }

    @Test func theLineDrawsInFourTenthsOfASecond() {
        let timing = ConnectFourOutcomeTiming.self

        #expect(timing.lineProgress(elapsed: -1) == 0)
        #expect(timing.lineProgress(elapsed: 0) == 0)
        #expect(isClose(timing.lineProgress(elapsed: 0.2), 0.5))
        #expect(timing.lineProgress(elapsed: 0.4) == 1)
        #expect(timing.lineProgress(elapsed: .infinity) == 1)
    }

    @Test func aWinDimsTheOtherDiscsToFortyPercentAndKeepsThemThere() {
        let timing = ConnectFourOutcomeTiming.self

        #expect(timing.veil(elapsed: 0, isDraw: false) == 0)
        #expect(isClose(timing.veil(elapsed: 0.2, isDraw: false), 0.6))
        #expect(isClose(timing.veil(elapsed: .infinity, isDraw: false), 0.6))
    }

    @Test func aDrawDimsEveryDiscToSixtyPercentThenLetsThemRecover() {
        let timing = ConnectFourOutcomeTiming.self

        #expect(timing.veil(elapsed: 0, isDraw: true) == 0)
        #expect(isClose(timing.veil(elapsed: 0.3, isDraw: true), 0.4))
        #expect(timing.veil(elapsed: 0.65, isDraw: true) == 0)
        #expect(timing.veil(elapsed: .infinity, isDraw: true) == 0)
    }

    @Test func theHighlightSettlesAfterTheBloomAndADrawSettlesSooner() {
        let timing = ConnectFourOutcomeTiming.self

        #expect(isClose(timing.settleTime(cellCount: 4, isDraw: false, bloomDuration: 0.9), 1.45))
        #expect(isClose(timing.settleTime(cellCount: 7, isDraw: false, bloomDuration: 0.9), 1.45))
        #expect(isClose(timing.settleTime(cellCount: 0, isDraw: true, bloomDuration: 0.9), 0.65))
    }

    @Test func theOutcomeStageKnowsWhenItStarted() {
        let date = Date(timeIntervalSince1970: 100)

        #expect(ConnectFourOutcomeStage.playing(date).startDate == date)
        #expect(ConnectFourOutcomeStage.settled.startDate == nil)
        #expect(ConnectFourOutcomeStage.idle.startDate == nil)
    }
}

/// How long the screen waits for a Connect Four move, from how far its disc falls.
struct ConnectFourDropTimingTests {
    @Test func aMoveTakesAsLongAsItsDiscFalls() throws {
        let one = try #require(ConnectFourBoard.replay([3]))
        let three = try #require(ConnectFourBoard.replay([3, 3, 3]))
        let mine = BoardMoveEvent(number: 1, move: 3, player: .one, isMine: true)
        let partner = BoardMoveEvent(number: 1, move: 3, player: .one, isMine: false)
        let bottom = ConnectFourDropMotion.forMove(landingRow: 5, isMine: true, reduceMotion: false)

        #expect(ConnectFourDropMotion.showDuration(of: mine, on: one) == .seconds(bottom.totalDuration))
        let short = try #require(ConnectFourDropMotion.showDuration(of: mine, on: three))
        let partners = try #require(ConnectFourDropMotion.showDuration(of: partner, on: one))
        #expect(short < .seconds(bottom.totalDuration))
        #expect(partners > .seconds(bottom.totalDuration))
        // A column with no disc holds no move to show.
        let empty = BoardMoveEvent(number: 1, move: 0, player: .one, isMine: true)
        #expect(ConnectFourDropMotion.showDuration(of: empty, on: one) == nil)
    }

    @MainActor
    @Test func theGamesFallbackTimingCoversTheLongestDrops() {
        let mine = ConnectFourDropMotion.forMove(landingRow: 5, isMine: true, reduceMotion: false)
        let partner = ConnectFourDropMotion.forMove(landingRow: 5, isMine: false, reduceMotion: false)

        #expect(ConnectFourGame.timing.mine >= .seconds(mine.totalDuration))
        #expect(ConnectFourGame.timing.partner >= .seconds(partner.totalDuration))
    }
}
