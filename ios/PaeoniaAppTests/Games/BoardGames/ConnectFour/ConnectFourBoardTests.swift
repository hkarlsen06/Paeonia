import Testing
@testable import PaeoniaApp

struct ConnectFourBoardTests {
    private func board(_ moves: [Int]) throws -> ConnectFourBoard {
        try #require(ConnectFourBoard.replay(moves))
    }

    /// Cell index for a row and column. Row 0 is the top row.
    private func cell(_ row: Int, _ column: Int) -> Int {
        row * ConnectFourBoard.columns + column
    }

    // MARK: Start and dropping

    @Test func aDiscFallsToTheLowestEmptyCellAndTheTurnPasses() throws {
        let board = try board([3, 3])

        #expect(board.cells[cell(5, 3)] == .one)
        #expect(board.cells[cell(4, 3)] == .two)
        #expect(board.discCount == 2)
        #expect(board.landingRow(column: 3) == 3)
        #expect(board.landingRow(column: 2) == 5)
        #expect(board.next == .one)
    }

    @Test func aFullColumnHasNoLandingRow() throws {
        let board = try board([0, 0, 0, 0, 0, 0])

        #expect(board.landingRow(column: 0) == nil)
        #expect(board.landingRow(column: -1) == nil)
        #expect(board.landingRow(column: 7) == nil)
    }

    // MARK: Wins

    @Test func fourInARowAcrossWins() throws {
        let board = try board([0, 0, 1, 1, 2, 2, 3])

        #expect(board.outcome == BoardOutcome(winner: .one, line: [35, 36, 37, 38]))
    }

    @Test func fourInAColumnWins() throws {
        let board = try board([0, 1, 0, 1, 0, 1, 0])

        #expect(board.outcome == BoardOutcome(winner: .one, line: [14, 21, 28, 35]))
    }

    @Test func aDiagonalRisingToTheRightWins() throws {
        let board = try board([0, 1, 1, 2, 3, 2, 2, 3, 6, 3, 3])

        #expect(board.outcome == BoardOutcome(winner: .one, line: [17, 23, 29, 35]))
    }

    @Test func aDiagonalFallingToTheRightWins() throws {
        let board = try board([6, 5, 5, 4, 3, 4, 4, 3, 0, 3, 3])

        #expect(board.outcome == BoardOutcome(winner: .one, line: [17, 25, 33, 41]))
    }

    @Test func playerTwoCanWinToo() throws {
        let board = try board([0, 1, 0, 1, 0, 1, 2, 1])

        #expect(board.outcome == BoardOutcome(winner: .two, line: [15, 22, 29, 36]))
    }

    @Test func fiveInARowLightsAllFiveDiscs() throws {
        // Player one fills in the gap at column 2 and joins two pairs into five.
        let board = try board([0, 0, 1, 1, 3, 3, 4, 4, 2])

        #expect(board.outcome == BoardOutcome(winner: .one, line: [35, 36, 37, 38, 39]))
    }

    @Test func threeInARowIsNotAWin() throws {
        let board = try board([0, 0, 1, 1, 2])

        #expect(board.outcome == nil)
    }

    // MARK: Draw

    /// A real game: 42 moves, 21 discs each, and no four in a row at any point.
    private let drawMoves = [
        1, 4, 6, 6, 6, 0, 2, 0, 3, 6, 3, 3, 5, 3, 6, 1, 0, 3, 0, 4, 3,
        5, 0, 6, 5, 2, 2, 5, 1, 2, 2, 0, 2, 5, 4, 5, 4, 4, 4, 1, 1, 1
    ]

    @Test func aFullBoardWithoutFourInARowIsADraw() throws {
        var board = ConnectFourBoard.initial
        for move in drawMoves.dropLast() {
            board = try #require(board.applying(move))
            #expect(board.outcome == nil)
        }
        #expect(board.discCount == 41)

        let lastMove = try #require(drawMoves.last)
        board = try #require(board.applying(lastMove))

        #expect(drawMoves.count == 42)
        #expect(board.discCount == 42)
        #expect(board.outcome == BoardOutcome(winner: nil, line: []))
        #expect(board.cells.count { $0 == .one } == 21)
        #expect(board.cells.count { $0 == .two } == 21)
        #expect((0..<7).allSatisfy { board.landingRow(column: $0) == nil })
    }

    // MARK: Illegal moves

    @Test func movesOutsideTheSevenColumnsAreIllegal() {
        let board = ConnectFourBoard.initial

        #expect(board.applying(-1) == nil)
        #expect(board.applying(7) == nil)
        #expect(board.applying(42) == nil)
    }

    @Test func aFullColumnRejectsAnotherDisc() throws {
        let board = try board([0, 0, 0, 0, 0, 0])

        #expect(!board.isLegal(0))
        #expect(board.isLegal(1))
    }

    @Test func noMoveIsLegalAfterTheGameEnds() throws {
        let board = try board([0, 0, 1, 1, 2, 2, 3])

        #expect((0..<7).allSatisfy { !board.isLegal($0) })
    }

    // MARK: Random games

    @Test func randomGamesAlwaysEndAndReplayToTheSameBoard() {
        for finished in playRandomGames(ConnectFourBoard.self, maxMoves: 42) {
            guard let outcome = finished.outcome else { continue }
            if let winner = outcome.winner {
                #expect(outcome.line.count >= 4)
                #expect(outcome.line == outcome.line.sorted())
                #expect(outcome.line.allSatisfy { finished.cells[$0] == winner })
            } else {
                #expect(outcome.line.isEmpty)
                #expect(finished.discCount == 42)
            }
        }
    }
}
