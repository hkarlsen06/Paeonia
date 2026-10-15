import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

/// Games used by the Ultimate Tic-Tac-Toe board tests.
private enum UltimateTicTacToeFixtures {
    /// Player one opened in the middle, so player two must play in board 4.
    static let forcedMoves = [40]
    /// Player one took board 3, and the last move sent player one to it. Any
    /// open board will do.
    static let freeMoves = [32, 48, 29, 21, 35, 74, 19, 13, 42, 57]
    /// Player two's last move took board 4 with the bottom row. Player one is
    /// sent to board 8.
    static let wonLastMoves = [40, 43, 67, 42, 58, 44]
    /// Player one wins the right column of small boards on the last move.
    static let finishedMoves = [
        20, 26, 79, 63, 8, 74, 24, 56, 22, 44, 73, 11, 58,
        41, 49, 40, 42, 59, 46, 14, 52, 65, 29, 17, 76
    ]

    static func played(_ moves: [Int]) throws -> UltimateTicTacToeBoard {
        try #require(UltimateTicTacToeBoard.replay(moves))
    }

    static func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    static func isClose(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    static func isClose(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        isClose(lhs.x, rhs.x) && isClose(lhs.y, rhs.y)
    }
}

/// The layout of the board, the zoom transform and the hit tests.
struct UltimateTicTacToeGeometryTests {
    private let geometry = UltimateTicTacToeBoardGeometry(side: 400)

    private func center(_ rect: CGRect) -> CGPoint {
        UltimateTicTacToeFixtures.center(rect)
    }

    private func isClose(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        UltimateTicTacToeFixtures.isClose(lhs, rhs)
    }

    private func isClose(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        UltimateTicTacToeFixtures.isClose(lhs, rhs)
    }

    // MARK: Layout

    @Test func smallBoardsAreSeparatedByGapsOfFourPercentOfTheSide() {
        let across = geometry.smallRect(1).minX - geometry.smallRect(0).maxX
        let down = geometry.smallRect(3).minY - geometry.smallRect(0).maxY

        #expect(isClose(across, 16))
        #expect(isClose(down, 16))
    }

    @Test func theNineSmallBoardsSitInsideTheBoard() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)

        for index in 0..<9 {
            #expect(bounds.contains(geometry.smallRect(index)))
        }
        #expect(isClose(geometry.smallRect(8).maxX, 400 - geometry.margin))
    }

    @Test func cellsStayInsideTheirSmallBoard() {
        for board in 0..<9 {
            for cell in 0..<9 {
                #expect(geometry.smallRect(board).contains(geometry.cellRect(board: board, cell: cell)))
            }
        }
    }

    @Test func theCenterOfEveryCellHitsThatCell() {
        for board in 0..<9 {
            for cell in 0..<9 {
                let point = center(geometry.cellRect(board: board, cell: cell))

                #expect(geometry.move(at: point) == board * 9 + cell)
            }
        }
    }

    @Test func aPointInTheMiddleOfAGapBelongsToTheNearerSide() {
        let gapMiddle = geometry.smallRect(0).maxX + geometry.gap / 2
        let y = geometry.smallRect(0).midY

        #expect(geometry.nearestBoard(to: CGPoint(x: gapMiddle - 0.1, y: y)) == 0)
        #expect(geometry.nearestBoard(to: CGPoint(x: gapMiddle + 0.1, y: y)) == 1)
    }

    @Test func aPointInTheGapStillPlaysACellOfTheNearestBoard() {
        let rect = geometry.smallRect(4)
        let justOutside = CGPoint(x: rect.minX - 2, y: rect.minY - 2)

        #expect(geometry.move(at: justOutside) == UltimateTicTacToeBoard.move(board: 4, cell: 0))
    }

    @Test func pointsOutsideTheBoardCountAsTheNearestEdgeCell() {
        #expect(geometry.move(at: CGPoint(x: -50, y: -50)) == 0)
        #expect(geometry.move(at: CGPoint(x: 900, y: 900)) == 80)
    }

    @Test func aSmallBoardSplitsIntoThirdsWithNoPadding() {
        let small = UltimateTicTacToeSmallBoardGeometry(side: 90)

        #expect(small.cell(at: CGPoint(x: 1, y: 1)) == 0)
        #expect(small.cell(at: CGPoint(x: 89, y: 1)) == 2)
        #expect(small.cell(at: CGPoint(x: 45, y: 45)) == 4)
        #expect(small.cell(at: CGPoint(x: 1, y: 89)) == 6)
        #expect(small.hitRect(5) == CGRect(x: 60, y: 30, width: 30, height: 30))
    }

    @Test func aStrikeLineRunsPastTheEndsOfTheWinningCells() throws {
        let small = UltimateTicTacToeSmallBoardGeometry(side: 90)
        let line = try #require(small.strikeLine(through: [2, 5, 8]))

        #expect(isClose(line.start.x, small.cellCenter(2).x))
        #expect(line.start.y < small.cellCenter(2).y)
        #expect(line.end.y > small.cellCenter(8).y)
        #expect(small.strikeLine(through: []) == nil)
    }

    // MARK: Zoom transform

    @Test func aFocusedBoardFillsNinetyPercentOfTheViewAndSitsInTheMiddle() {
        let transform = geometry.transform(focusing: 4)
        let rect = geometry.smallRect(4)
        let topLeft = transform.apply(CGPoint(x: rect.minX, y: rect.minY))
        let bottomRight = transform.apply(CGPoint(x: rect.maxX, y: rect.maxY))

        #expect(isClose(bottomRight.x - topLeft.x, 360))
        #expect(isClose(topLeft.x, 20))
        #expect(isClose(topLeft.y, 20))
    }

    @Test func everyBoardZoomsToTheMiddleOfTheView() {
        for board in 0..<9 {
            let middle = geometry.transform(focusing: board).apply(geometry.center(of: board))

            #expect(isClose(middle, CGPoint(x: 200, y: 200)))
        }
    }

    @Test func theTransformInvertsBackToBoardCoordinates() {
        let transform = geometry.transform(focusing: 2)
        let point = CGPoint(x: 123, y: 321)

        #expect(isClose(transform.invert(transform.apply(point)), point))
    }

    @Test func noFocusIsTheIdentityAndAZeroSizedBoardDoesNotZoom() {
        #expect(geometry.transform(focusing: nil) == .identity)
        #expect(UltimateTicTacToeBoardGeometry(side: 0).transform(focusing: 4) == .identity)
    }

    @Test func theLineThroughThreeBoardsRunsBetweenTheFirstAndTheLastCenter() throws {
        let ends = try #require(geometry.lineEnds(through: [2, 5, 8]))
        let middle = try #require(geometry.lineMidpoint(through: [2, 5, 8]))

        #expect(isClose(ends.start, geometry.center(of: 2)))
        #expect(isClose(ends.end, geometry.center(of: 8)))
        #expect(isClose(middle, geometry.center(of: 5)))
        #expect(geometry.lineMidpoint(through: []) == nil)
    }
}

/// Where the camera rests and what a tap means.
struct UltimateTicTacToeZoomTests {
    private let geometry = UltimateTicTacToeBoardGeometry(side: 400)

    private func played(_ moves: [Int]) throws -> UltimateTicTacToeBoard {
        try UltimateTicTacToeFixtures.played(moves)
    }

    private func center(_ rect: CGRect) -> CGPoint {
        UltimateTicTacToeFixtures.center(rect)
    }

    private func zoom(
        _ board: UltimateTicTacToeBoard,
        canPlay: Bool = true,
        zoomEnabled: Bool = true,
        choice: UltimateTicTacToeZoom.Choice = .automatic
    ) -> UltimateTicTacToeZoom {
        UltimateTicTacToeZoom(board: board, canPlay: canPlay, zoomEnabled: zoomEnabled, choice: choice)
    }

    private var forcedMoves: [Int] { UltimateTicTacToeFixtures.forcedMoves }
    private var freeMoves: [Int] { UltimateTicTacToeFixtures.freeMoves }
    private var finishedMoves: [Int] { UltimateTicTacToeFixtures.finishedMoves }

    // MARK: Where the camera rests

    @Test func aBoardIHaveToPlayInZoomsInOnMyTurn() throws {
        let model = zoom(try played(forcedMoves))

        #expect(model.board.forced == 4)
        #expect(model.restingFocus == 4)
    }

    @Test func whenIMayChooseTheWholeBoardShows() throws {
        let model = zoom(try played(freeMoves))

        #expect(model.board.forced == nil)
        #expect(model.restingFocus == nil)
    }

    @Test func theWholeBoardShowsWhileItIsNotMyTurn() throws {
        let forced = try played(forcedMoves)

        #expect(zoom(forced, canPlay: false).restingFocus == nil)
    }

    @Test func voiceOverNeverZooms() throws {
        let forced = try played(forcedMoves)

        #expect(zoom(forced, zoomEnabled: false).restingFocus == nil)
    }

    @Test func aFinishedGameShowsTheWholeBoard() throws {
        let finished = try played(finishedMoves)

        #expect(finished.outcome != nil)
        #expect(zoom(finished).restingFocus == nil)
    }

    @Test func aBoardIPickedZoomsInAsLongAsItIsOpen() throws {
        let free = try played(freeMoves)

        #expect(zoom(free, choice: .board(0)).restingFocus == 0)
        #expect(zoom(free, choice: .board(3)).restingFocus == nil)
    }

    @Test func zoomingOutByChoiceKeepsTheWholeBoardEvenWhenSentToOneBoard() throws {
        let forced = try played(forcedMoves)

        #expect(zoom(forced, choice: .wholeBoard).restingFocus == nil)
    }

    @Test func aPickOutsideTheBoardIAmSentToIsIgnored() throws {
        let forced = try played(forcedMoves)

        #expect(zoom(forced, choice: .board(2)).restingFocus == 4)
    }

    // MARK: Taps

    @Test func tappingAnOpenBoardWhileChoosingZoomsIntoIt() throws {
        let model = zoom(try played(freeMoves))
        let tap = model.tap(at: geometry.center(of: 0), geometry: geometry, focus: nil)

        #expect(tap == .focus(0))
    }

    @Test func tappingAClosedBoardOrTappingOutOfTurnDoesNothing() throws {
        let free = try played(freeMoves)

        #expect(zoom(free).tap(at: geometry.center(of: 3), geometry: geometry, focus: nil) == .ignore)
        #expect(zoom(free, canPlay: false).tap(at: geometry.center(of: 0), geometry: geometry, focus: nil) == .ignore)
    }

    @Test func whenSentToOneBoardOnlyThatBoardCanBeZoomedInto() throws {
        let model = zoom(try played(forcedMoves))

        #expect(model.tap(at: geometry.center(of: 0), geometry: geometry, focus: nil) == .ignore)
        #expect(model.tap(at: geometry.center(of: 4), geometry: geometry, focus: nil) == .focus(4))
    }

    @Test func tappingACellOfTheFocusedBoardPlaysIt() throws {
        let model = zoom(try played(forcedMoves))
        let point = center(geometry.cellRect(board: 4, cell: 0))

        #expect(model.tap(at: point, geometry: geometry, focus: 4) == .play(36))
    }

    @Test func tappingATakenCellDoesNothing() throws {
        let model = zoom(try played(forcedMoves))
        let point = center(geometry.cellRect(board: 4, cell: 4))

        #expect(model.tap(at: point, geometry: geometry, focus: 4) == .ignore)
    }

    @Test func tappingOutsideTheFocusedBoardZoomsOut() throws {
        let model = zoom(try played(forcedMoves))

        #expect(model.tap(at: geometry.center(of: 0), geometry: geometry, focus: 4) == .zoomOut)
    }

    @Test func withoutZoomATapPlaysTheLegalCellItIsClosestTo() throws {
        let model = zoom(try played(forcedMoves), zoomEnabled: false)
        let rect = geometry.smallRect(4)
        let inTheGap = CGPoint(x: rect.minX - 2, y: rect.minY - 2)

        let cellTwo = center(geometry.cellRect(board: 4, cell: 2))

        #expect(model.tap(at: cellTwo, geometry: geometry, focus: nil) == .play(38))
        #expect(model.tap(at: inTheGap, geometry: geometry, focus: nil) == .play(36))
        #expect(model.tap(at: geometry.center(of: 0), geometry: geometry, focus: nil) == .ignore)
    }

    @Test func withoutZoomATapOutOfTurnDoesNothing() throws {
        let model = zoom(try played(forcedMoves), canPlay: false, zoomEnabled: false)

        #expect(model.tap(at: center(geometry.cellRect(board: 4, cell: 2)), geometry: geometry, focus: nil) == .ignore)
    }

    @Test func aFinishedGameIgnoresTaps() throws {
        let model = zoom(try played(finishedMoves), zoomEnabled: false)

        #expect(model.tap(at: geometry.center(of: 0), geometry: geometry, focus: nil) == .ignore)
    }

    @Test func onlyAPinchInZoomsOut() {
        #expect(UltimateTicTacToeZoom.isZoomOutPinch(0.8))
        #expect(!UltimateTicTacToeZoom.isZoomOutPinch(0.9))
        #expect(!UltimateTicTacToeZoom.isZoomOutPinch(1.3))
    }
}

/// What the board draws while a move arrives and after the game ends.
struct UltimateTicTacToePresentationTests {
    private func played(_ moves: [Int]) throws -> UltimateTicTacToeBoard {
        try UltimateTicTacToeFixtures.played(moves)
    }

    private var forcedMoves: [Int] { UltimateTicTacToeFixtures.forcedMoves }
    private var freeMoves: [Int] { UltimateTicTacToeFixtures.freeMoves }
    private var wonLastMoves: [Int] { UltimateTicTacToeFixtures.wonLastMoves }
    private var finishedMoves: [Int] { UltimateTicTacToeFixtures.finishedMoves }

    // MARK: Moves that are still arriving

    @Test func anArrivingPartnerMoveHidesItsMarkAndTheBoardItClosed() throws {
        let board = try played(wonLastMoves)
        let event = BoardMoveEvent(number: 6, move: 44, player: .two, isMine: false)
        let hold = try #require(UltimateTicTacToeHold.arriving(event, on: board))

        #expect(hold.hiddenMove == 44)
        #expect(hold.unclosedBoard == 4)
        #expect(hold.isHolding(4))
        #expect(!hold.isHolding(3))
    }

    @Test func myArrivingMoveShowsItsMarkButHoldsTheBoardItClosed() throws {
        let board = try played(wonLastMoves)
        let event = BoardMoveEvent(number: 6, move: 44, player: .two, isMine: true)
        let hold = try #require(UltimateTicTacToeHold.arriving(event, on: board))

        #expect(hold.hiddenMove == nil)
        #expect(hold.unclosedBoard == 4)
    }

    @Test func aMoveThatClosesNothingHoldsNoBoard() throws {
        let board = try played(forcedMoves)
        let event = BoardMoveEvent(number: 1, move: 40, player: .one, isMine: false)
        let hold = try #require(UltimateTicTacToeHold.arriving(event, on: board))

        #expect(hold.hiddenMove == 40)
        #expect(hold.unclosedBoard == nil)
    }

    @Test func aMoveTheBoardDoesNotContainHoldsNothing() throws {
        let board = try played(forcedMoves)
        let stale = BoardMoveEvent(number: 1, move: 0, player: .one, isMine: false)

        #expect(UltimateTicTacToeHold.arriving(stale, on: board) == nil)
    }

    @Test func aMoveIsPendingUntilThePlaybackHasHandledIt() throws {
        let board = try played(forcedMoves)
        let event = BoardMoveEvent(number: 1, move: 40, player: .one, isMine: false)

        func pending(handled: Int?, enabled: Bool = true) -> UltimateTicTacToeHold? {
            UltimateTicTacToeHold.pending(lastMove: event, handled: handled, board: board, enabled: enabled)
        }

        #expect(pending(handled: nil)?.hiddenMove == 40)
        #expect(pending(handled: 1) == nil)
        #expect(pending(handled: nil, enabled: false) == nil)
        #expect(UltimateTicTacToeHold.pending(lastMove: nil, handled: nil, board: board, enabled: true) == nil)
    }

    // MARK: What each small board draws

    @Test func aHeldBackMarkReadsAsEmptyAndTheClosedBoardAsOpen() throws {
        let board = try played(wonLastMoves)
        let hold = UltimateTicTacToeHold(hiddenMove: 44, unclosedBoard: 4)
        let held = UltimateTicTacToeSmallBoardContent(board: board, index: 4, hold: hold)
        let shown = UltimateTicTacToeSmallBoardContent(board: board, index: 4, hold: .none)

        #expect(held.cells[8] == nil)
        #expect(held.cells[6] == .two)
        #expect(held.state == .open)
        #expect(held.winningCells.isEmpty)
        #expect(shown.cells[8] == .two)
        #expect(shown.state == .won(.two))
        #expect(shown.winningCells == [6, 7, 8])
    }

    // MARK: Glow, dim and the outcome

    @Test func theBoardTheNextMoveMayUseGlowsAndOtherOpenBoardsDim() throws {
        let look = UltimateTicTacToeLook(
            board: try played(forcedMoves), hold: .none, focus: nil, glowHeld: false, outcome: .idle
        )

        let dimmed = UltimateTicTacToeEmphasis(glow: .none, opacity: UltimateTicTacToeLook.unusableOpacity)

        #expect(look.emphasis(of: 4) == UltimateTicTacToeEmphasis(glow: .next, opacity: 1))
        #expect(look.emphasis(of: 0) == dimmed)
    }

    @Test func aClosedBoardIsNeitherDimmedNorGlowing() throws {
        let look = UltimateTicTacToeLook(
            board: try played(freeMoves), hold: .none, focus: nil, glowHeld: false, outcome: .idle
        )

        #expect(look.emphasis(of: 3) == .plain)
        #expect(look.emphasis(of: 0) == UltimateTicTacToeEmphasis(glow: .next, opacity: 1))
    }

    @Test func nothingGlowsOrDimsWhileMyPartnersMovePlays() throws {
        let look = UltimateTicTacToeLook(
            board: try played(forcedMoves), hold: .none, focus: 0, glowHeld: true, outcome: .idle
        )

        for index in 0..<9 {
            #expect(look.emphasis(of: index) == .plain)
        }
    }

    @Test func theWinningBoardsLightUpInOrderAndTheRestDims() throws {
        let finished = try played(finishedMoves)
        let result = try #require(finished.outcome)
        let halfway = UltimateTicTacToeOutcomeState(isDimmed: true, litCount: 2, lineProgress: 0.5)
        let look = UltimateTicTacToeLook(board: finished, hold: .none, focus: nil, glowHeld: false, outcome: halfway)

        #expect(result.winner == .one)
        #expect(result.line == [2, 5, 8])
        #expect(look.emphasis(of: 2) == UltimateTicTacToeEmphasis(glow: .winner, opacity: 1))
        #expect(look.emphasis(of: 5) == UltimateTicTacToeEmphasis(glow: .winner, opacity: 1))
        #expect(look.emphasis(of: 8) == .plain)
        #expect(look.emphasis(of: 0) == UltimateTicTacToeEmphasis(glow: .none, opacity: 0.4))
    }

    @Test func beforeTheHighlightStartsTheFinishedBoardLooksPlain() throws {
        let look = UltimateTicTacToeLook(
            board: try played(finishedMoves), hold: .none, focus: nil, glowHeld: false, outcome: .idle
        )

        for index in 0..<9 {
            #expect(look.emphasis(of: index) == .plain)
        }
    }

    @Test func theSettledHighlightLightsAndDrawsTheWholeLine() throws {
        let finished = try played(finishedMoves)
        let result = try #require(finished.outcome)
        let settled = UltimateTicTacToeOutcomeState.settled(for: result)

        #expect(settled == UltimateTicTacToeOutcomeState(isDimmed: true, litCount: 3, lineProgress: 1))
        #expect(UltimateTicTacToeOutcomeState.settled(for: nil) == .idle)
    }

    @Test func aDrawSettlesDimWithNoLine() {
        let settled = UltimateTicTacToeOutcomeState.settled(for: BoardOutcome(winner: nil, line: []))

        #expect(settled.drawOpacity == UltimateTicTacToeOutcomeState.drawSettledOpacity)
        #expect(!settled.isDimmed)
        #expect(settled.lineProgress == 0)
    }

    @Test func oneMoveThatFinishesTwoLinesDrawsBoth() {
        let two = BoardOutcome(winner: .one, line: [0, 1, 2, 4, 8])

        let one = BoardOutcome(winner: .one, line: [2, 5, 8])

        #expect(UltimateTicTacToeOutcomeState.winningRows(of: two) == [[0, 1, 2], [0, 4, 8]])
        #expect(UltimateTicTacToeOutcomeState.winningRows(of: one) == [[2, 5, 8]])
    }

    // MARK: Scripts

    @Test func aWinLightsTheBoardsInOrderThenDrawsTheLineAndBlooms() {
        let beats = UltimateTicTacToeOutcomeScript.beats(lineCount: 3, isDraw: false)
        let times = beats.map(\.at)

        #expect(times == times.sorted())
        #expect(beats.first { $0.event == .dimRest }?.at == 0)
        #expect(beats.first { $0.event == .light(0) }?.at == 0)
        #expect(beats.first { $0.event == .light(1) }?.at == 0.1)
        #expect(beats.first { $0.event == .light(2) }?.at == 0.2)
        #expect(beats.first { $0.event == .drawLine }?.at == 0.15)
        #expect(beats.first { $0.event == .bloom }?.at == 0.55)
        #expect(beats.last?.event == .clearBloom)
    }

    @Test func aDrawDipsThenSettlesWithoutABloom() {
        let beats = UltimateTicTacToeOutcomeScript.beats(lineCount: 0, isDraw: true)

        #expect(beats.map(\.event) == [.dipDraw, .settleDraw])
    }

    @Test func theMoveDurationsCoverTheirBeats() {
        typealias Timing = UltimateTicTacToeTiming
        let partner = Timing.pullBack + Timing.zoomToMove + Timing.markDraw + Timing.hold

        #expect(UltimateTicTacToeTiming.partner == .milliseconds(Int((partner * 1_000).rounded())))
        #expect(UltimateTicTacToeTiming.mine < UltimateTicTacToeTiming.partner)
    }
}
