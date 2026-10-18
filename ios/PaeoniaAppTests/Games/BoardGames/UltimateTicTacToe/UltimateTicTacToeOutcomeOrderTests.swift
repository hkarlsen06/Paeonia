import CoreGraphics
import Testing
@testable import PaeoniaApp

/// The end of an Ultimate Tic-Tac-Toe game: the winning boards light up from
/// the board that won it, and my game-ending move hands over to the outcome
/// once its small board has closed.
struct UltimateTicTacToeOutcomeOrderTests {
    private typealias Fixtures = UltimateTicTacToeFixtures

    @Test func theWinningBoardsLightUpFromTheBoardThatWonTheGame() throws {
        let finished = try Fixtures.played(Fixtures.finishedMoves)
        let result = try #require(finished.outcome)
        // The last move took board 8.
        let started = UltimateTicTacToeOutcomeState(isDimmed: true, litCount: 1, lineProgress: 0.5, origin: 8)
        let look = UltimateTicTacToeLook(board: finished, hold: .none, focus: nil, glowHeld: false, outcome: started)

        #expect(started.litOrder(of: result) == [8, 5, 2])
        #expect(started.fromOrigin([2, 5, 8]) == [8, 5, 2])
        #expect(UltimateTicTacToeOutcomeState.idle.fromOrigin([2, 5, 8]) == [2, 5, 8])
        #expect(look.emphasis(of: 8) == UltimateTicTacToeEmphasis(glow: .winner, opacity: 1))
        #expect(look.emphasis(of: 2) == .plain)
    }

    @MainActor
    @Test func myMoveThatEndsTheGameTakesOnlyItsClosingBeat() throws {
        let finished = try Fixtures.played(Fixtures.finishedMoves)
        let ongoing = try Fixtures.played(Array(Fixtures.finishedMoves.dropLast()))
        let exact = try #require(UltimateTicTacToeBoardView.moveTiming.exact)
        let number = Fixtures.finishedMoves.count
        let mine = BoardMoveEvent(number: number, move: 76, player: .one, isMine: true)
        let partners = BoardMoveEvent(number: number, move: 76, player: .one, isMine: false)

        #expect(exact(mine, finished) == UltimateTicTacToeTiming.mineEnding)
        #expect(exact(partners, finished) == nil)
        #expect(exact(mine, ongoing) == nil)
    }
}
