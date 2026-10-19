import Testing
@testable import PaeoniaApp

struct DotsAndBoxesBoardTests {
    private func board(_ moves: [Int]) throws -> DotsAndBoxesBoard {
        try #require(DotsAndBoxesBoard.replay(moves))
    }

    // MARK: Start and line numbering

    @Test func lineIndexesDecodeToTheirPlaceOnTheGrid() {
        let first = DotsAndBoxesBoard.LinePosition(isHorizontal: true, row: 0, column: 0)
        let lastHorizontal = DotsAndBoxesBoard.LinePosition(isHorizontal: true, row: 4, column: 3)
        let firstVertical = DotsAndBoxesBoard.LinePosition(isHorizontal: false, row: 0, column: 0)
        let inside = DotsAndBoxesBoard.LinePosition(isHorizontal: false, row: 1, column: 1)
        let last = DotsAndBoxesBoard.LinePosition(isHorizontal: false, row: 3, column: 4)

        #expect(DotsAndBoxesBoard.position(of: 0) == first)
        #expect(DotsAndBoxesBoard.position(of: 19) == lastHorizontal)
        #expect(DotsAndBoxesBoard.position(of: 20) == firstVertical)
        #expect(DotsAndBoxesBoard.position(of: 26) == inside)
        #expect(DotsAndBoxesBoard.position(of: 39) == last)
        #expect(DotsAndBoxesBoard.position(of: -1) == nil)
        #expect(DotsAndBoxesBoard.position(of: 40) == nil)
    }

    @Test func aBoxHasItsTopBottomLeftAndRightLines() {
        #expect(DotsAndBoxesBoard.lines(of: 0) == [0, 4, 20, 21])
        #expect(DotsAndBoxesBoard.lines(of: 5) == [5, 9, 26, 27])
        #expect(DotsAndBoxesBoard.lines(of: 15) == [15, 19, 38, 39])
    }

    @Test func aLineBordersOneOrTwoBoxes() {
        // Outer lines touch one box.
        #expect(DotsAndBoxesBoard.boxes(touching: 0) == [0])
        #expect(DotsAndBoxesBoard.boxes(touching: 19) == [15])
        #expect(DotsAndBoxesBoard.boxes(touching: 20) == [0])
        #expect(DotsAndBoxesBoard.boxes(touching: 39) == [15])
        // Inner lines touch two, in ascending order.
        #expect(DotsAndBoxesBoard.boxes(touching: 5) == [1, 5])
        #expect(DotsAndBoxesBoard.boxes(touching: 21) == [0, 1])
        #expect(DotsAndBoxesBoard.boxes(touching: 40).isEmpty)
    }

    @Test func everyBoxIsTouchedByEachOfItsLines() {
        for box in 0..<16 {
            for line in DotsAndBoxesBoard.lines(of: box) {
                #expect(DotsAndBoxesBoard.boxes(touching: line).contains(box))
            }
        }
    }

    // MARK: Turns and boxes

    @Test func aLineThatClosesNoBoxPassesTheTurn() throws {
        let board = try board([0])

        #expect(board.lines[0] == .one)
        #expect(board.next == .two)
        #expect(board.boxCount(for: .one) == 0)
    }

    @Test func closingABoxKeepsTheTurnAndOwnsTheBox() throws {
        let board = try board([0, 4, 20, 21])

        #expect(board.boxes[0] == .two)
        #expect(board.boxCount(for: .two) == 1)
        #expect(board.boxCount(for: .one) == 0)
        #expect(board.next == .two)
        #expect(board.outcome == nil)
    }

    @Test func oneLineCanCloseTwoBoxes() throws {
        // Boxes 0 and 1 share line 21. Player one draws it last and keeps the turn.
        let board = try board([0, 4, 20, 1, 5, 22, 21])

        #expect(board.boxes[0] == .one)
        #expect(board.boxes[1] == .one)
        #expect(board.boxCount(for: .one) == 2)
        #expect(board.next == .one)
    }

    @Test func theTurnPassesAfterTheExtraLineClosesNothing() throws {
        // Player two closes box 0 with line 21, then draws line 22 and closes nothing.
        let board = try board([0, 4, 20, 21, 22])

        #expect(board.boxes[0] == .two)
        #expect(board.boxes[1] == nil)
        #expect(board.next == .one)
    }

    // MARK: Whole games

    @Test func drawingLinesInOrderEndsEightBoxesEach() throws {
        let board = try board(Array(0..<40))

        #expect(board.boxCount(for: .one) == 8)
        #expect(board.boxCount(for: .two) == 8)
        #expect(board.outcome == BoardOutcome(winner: nil, line: []))
    }

    @Test func moreBoxesWinsAndTheOutcomeListsTheWinnersBoxes() throws {
        // Line 25 first, then the rest in order. Player one closes boxes 0 to 7 and 12 to 15.
        let moves = [25] + Array(0..<25) + Array(26..<40)
        let board = try board(moves)

        #expect(board.boxCount(for: .one) == 12)
        #expect(board.boxCount(for: .two) == 4)
        #expect(board.outcome == BoardOutcome(winner: .one, line: [0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15]))
    }

    @Test func playerTwoCanWin() throws {
        // Lines 22 and 25 first, then the rest in order. Player two closes boxes 0 to 7 and 12 to 15.
        let moves = [22, 25] + Array(0..<22) + [23, 24] + Array(26..<40)
        let board = try board(moves)

        #expect(board.boxCount(for: .two) == 12)
        #expect(board.outcome == BoardOutcome(winner: .two, line: [0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15]))
    }

    @Test func theGameIsNotOverUntilEveryLineIsDrawn() throws {
        let board = try board(Array(0..<39))

        #expect(board.outcome == nil)
        #expect(board.isLegal(39))
    }

    // MARK: Illegal moves

    @Test func linesOutsideTheBoardAreIllegal() {
        let board = DotsAndBoxesBoard.initial

        #expect(board.applying(-1) == nil)
        #expect(board.applying(40) == nil)
    }

    @Test func aDrawnLineCannotBeDrawnAgain() throws {
        let board = try board([7])

        #expect(board.applying(7) == nil)
        #expect(board.isLegal(8))
    }

    @Test func noLineIsLegalAfterTheGameEnds() throws {
        let board = try board(Array(0..<40))

        #expect((0..<40).allSatisfy { !board.isLegal($0) })
    }

    // MARK: Random games

    @Test func randomGamesAlwaysEndAndReplayToTheSameBoard() {
        for finished in playRandomGames(DotsAndBoxesBoard.self, maxMoves: 40) {
            #expect(finished.lines.allSatisfy { $0 != nil })
            #expect(finished.boxes.allSatisfy { $0 != nil })
            #expect(finished.boxCount(for: .one) + finished.boxCount(for: .two) == 16)
            guard let outcome = finished.outcome else { continue }
            if let winner = outcome.winner {
                #expect(outcome.line.count == finished.boxCount(for: winner))
                #expect(outcome.line.allSatisfy { finished.boxes[$0] == winner })
                #expect(outcome.line == outcome.line.sorted())
            } else {
                #expect(outcome.line.isEmpty)
                #expect(finished.boxCount(for: .one) == 8)
            }
        }
    }
}
