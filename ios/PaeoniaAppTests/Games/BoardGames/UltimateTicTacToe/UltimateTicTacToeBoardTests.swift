import Testing
@testable import PaeoniaApp

struct UltimateTicTacToeBoardTests {
    private func board(_ moves: [Int]) throws -> UltimateTicTacToeBoard {
        try #require(UltimateTicTacToeBoard.replay(moves))
    }

    private func move(_ board: Int, _ cell: Int) -> Int {
        UltimateTicTacToeBoard.move(board: board, cell: cell)
    }

    /// Player one wins board 0 with cells 3, 4 and 5. Player two plays cell 0 of
    /// boards 2, 4, 3 and 5 to send player one back to board 0 each time.
    private let winsBoardZero = [9, 1, 11, 18, 4, 36, 3, 27, 5]

    // MARK: Start and forced boards

    @Test func theEmptyBoardAllowsAnyCellAndPlayerOneMovesFirst() {
        let board = UltimateTicTacToeBoard.initial

        #expect(UltimateTicTacToeBoard.moveLimit == 81)
        #expect(board.cells.count == 81)
        #expect(board.cells.allSatisfy { $0 == nil })
        #expect(board.boards == Array(repeating: .open, count: 9))
        #expect(board.forced == nil)
        #expect(board.openBoards == Array(0..<9))
        #expect(board.next == .one)
        #expect(board.outcome == nil)
        #expect((0..<81).allSatisfy { board.isLegal($0) })
    }

    @Test func theCellYouPlayChoosesTheBoardYourOpponentPlaysIn() throws {
        let board = try board([move(0, 4)])

        #expect(board.cells[4] == .one)
        #expect(board.forced == 4)
        #expect(board.openBoards == [4])
        #expect(board.next == .two)
        #expect((0..<81).filter { board.isLegal($0) } == Array(36..<45))
    }

    @Test func playingOutsideTheForcedBoardIsIllegal() throws {
        let board = try board([move(0, 4)])

        #expect(board.applying(move(0, 1)) == nil)
        #expect(board.applying(move(5, 5)) == nil)
        #expect(board.applying(move(4, 0)) != nil)
    }

    @Test func aTakenCellCannotBePlayedAgain() throws {
        // Player one takes cell 4 of board 0, player two answers in board 4 and sends them back.
        let board = try board([move(0, 4), move(4, 0)])

        #expect(board.forced == 0)
        #expect(board.applying(move(0, 4)) == nil)
        #expect(board.applying(move(0, 5)) != nil)
    }

    @Test func movesOutsideTheEightyOneCellsAreIllegal() {
        #expect(UltimateTicTacToeBoard.initial.applying(-1) == nil)
        #expect(UltimateTicTacToeBoard.initial.applying(81) == nil)
    }

    // MARK: Winning a small board

    @Test func threeInARowWinsASmallBoardAndShowsTheStrikeLine() throws {
        let board = try board(winsBoardZero)

        #expect(board.boards[0] == .won(.one))
        #expect(board.winningCells(of: 0) == [3, 4, 5])
        #expect(board.winningCells(of: 1).isEmpty)
        #expect(board.winningCells(of: 9).isEmpty)
        #expect(board.forced == 5)
        #expect(board.outcome == nil)
    }

    @Test func aWonBoardClosesToFurtherMoves() throws {
        let board = try board(winsBoardZero + [move(5, 0), move(1, 1)])

        #expect(board.boards[0] == .won(.one))
        // Player one now has a free move, but cell 6 of board 0 is closed.
        #expect(board.applying(move(0, 6)) == nil)
    }

    @Test func beingSentToAWonBoardGivesAFreeMove() throws {
        // Player two plays cell 0 of board 5, which points at the won board 0.
        let board = try board(winsBoardZero + [move(5, 0)])

        #expect(board.forced == nil)
        #expect(board.next == .one)
        #expect(board.openBoards == Array(1..<9))
        #expect(board.applying(move(7, 7)) != nil)
        #expect(board.applying(move(0, 6)) == nil)
    }

    // MARK: Full small boards

    /// Board 3 fills up with no three in a row after 25 moves (the last one is
    /// move 33). Two moves later, player one plays cell 3 of board 2.
    private let fillsBoardThree = [
        32, 53, 79, 71, 77, 48, 31, 37, 12, 35, 75, 34, 66, 27, 3, 29, 22, 39, 28, 15, 62, 78, 57, 30, 33, 56
    ]

    @Test func aSmallBoardWithoutThreeInARowIsFull() throws {
        let board = try board(Array(fillsBoardThree.prefix(25)))

        #expect(board.boards[3] == .full)
        #expect(board.boards.count { $0 == .full } == 1)
        #expect(board.boards.allSatisfy { $0 == .open || $0 == .full })
        #expect((27..<36).allSatisfy { board.cells[$0] != nil })
        #expect(board.winningCells(of: 3).isEmpty)
        #expect(board.applying(move(3, 1)) == nil)
    }

    @Test func beingSentToAFullBoardGivesAFreeMove() throws {
        let board = try board(fillsBoardThree)
        #expect(board.forced == 2)

        let after = try #require(board.applying(move(2, 3)))

        #expect(after.forced == nil)
        #expect(after.next == .two)
        #expect(after.openBoards == Array(0..<9).filter { $0 != 3 })
    }

    // MARK: Winning the game

    /// Player one wins boards 1 and 2 after board 0, taking the top row of the
    /// big board on move 17. Player two keeps handing over free moves.
    private let topRow = [9, 1, 11, 18, 4, 36, 3, 27, 5, 45, 10, 72, 24, 54, 25, 63, 26]

    @Test func threeSmallBoardsInARowWinTheGame() throws {
        let board = try board(topRow)

        #expect(board.boards.prefix(3).allSatisfy { $0 == .won(.one) })
        #expect(board.outcome == BoardOutcome(winner: .one, line: [0, 1, 2]))
        #expect(board.openBoards.isEmpty)
        #expect((0..<81).allSatisfy { !board.isLegal($0) })
    }

    @Test func theGameContinuesUntilTheThirdBoardIsWon() throws {
        let board = try board(Array(topRow.dropLast()))

        #expect(board.boards[0] == .won(.one))
        #expect(board.boards[1] == .won(.one))
        #expect(board.boards[2] == .open)
        #expect(board.outcome == nil)
    }

    /// Player one wins on move 43 and finishes two lines at once: the top row
    /// and the middle column share board 1.
    private let twoLinesAtOnce = [
        42, 56, 25, 65, 26, 72, 4, 36, 0, 7, 69, 58, 37, 13, 39, 29, 24, 61, 70, 68, 50, 46,
        14, 52, 71, 78, 57, 27, 8, 75, 32, 49, 43, 54, 17, 40, 41, 31, 44, 62, 28, 16, 11
    ]

    @Test func twoLinesAtOnceListEachBoardOnce() throws {
        let board = try board(twoLinesAtOnce)

        #expect(board.outcome == BoardOutcome(winner: .one, line: [0, 1, 2, 4, 7]))
    }

    // MARK: Drawing the game

    /// A real game of 44 moves that decides all nine boards and leaves no three
    /// in a row: player one holds 0, 4, 5 and 6, player two holds 1, 2, 3, 7 and 8.
    private let bigDraw = [
        11, 23, 48, 27, 4, 38, 26, 72, 7, 69, 62, 80, 79, 63, 3, 31, 37, 15, 61, 71, 73, 9,
        8, 76, 44, 70, 43, 35, 10, 12, 60, 20, 21, 5, 53, 19, 45, 1, 51, 39, 40, 0, 6, 18
    ]

    @Test func everyBoardDecidedWithoutThreeInARowIsADraw() throws {
        var board = UltimateTicTacToeBoard.initial
        for move in bigDraw.dropLast() {
            board = try #require(board.applying(move))
            #expect(board.outcome == nil)
        }
        #expect(board.openBoards.count == 1)

        let lastMove = try #require(bigDraw.last)
        board = try #require(board.applying(lastMove))

        #expect(bigDraw.count == 44)
        #expect(board.outcome == BoardOutcome(winner: nil, line: []))
        #expect(!board.boards.contains(.open))
        #expect(board.openBoards.isEmpty)
        #expect(board.boards == [
            .won(.one), .won(.two), .won(.two),
            .won(.two), .won(.one), .won(.one),
            .won(.one), .won(.two), .won(.two)
        ])
    }

    @Test func noMoveIsLegalAfterADraw() throws {
        let board = try board(bigDraw)

        #expect((0..<81).allSatisfy { !board.isLegal($0) })
    }

    // MARK: Random games

    @Test func randomGamesAlwaysEndAndReplayToTheSameBoard() {
        for finished in playRandomGames(UltimateTicTacToeBoard.self, maxMoves: 81) {
            guard let outcome = finished.outcome else { continue }
            if let winner = outcome.winner {
                #expect(outcome.line.count >= 3)
                #expect(outcome.line == outcome.line.sorted())
                #expect(outcome.line.allSatisfy { finished.boards[$0] == .won(winner) })
            } else {
                #expect(outcome.line.isEmpty)
                #expect(!finished.boards.contains(.open))
            }
            for board in finished.boards.indices {
                if case .won(let player) = finished.boards[board] {
                    let cells = finished.winningCells(of: board)
                    #expect(cells.count == 3)
                    #expect(cells.allSatisfy { finished.cells[$0] == player && $0 / 9 == board })
                }
            }
        }
    }
}
