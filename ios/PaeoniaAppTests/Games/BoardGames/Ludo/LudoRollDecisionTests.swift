import Foundation
import Testing
@testable import PaeoniaApp

struct LudoRollDecisionTests {
    private func board(_ moves: [Int]) throws -> LudoBoard {
        try #require(LudoBoard.replay(moves))
    }

    private let position = LudoPosition(gameID: UUID(), gameNumber: 3, moveCount: 4)

    // MARK: Passing by itself

    @Test func noPawnToMovePassesByItself() {
        #expect(LudoRollDecision.passesByItself(board: .initial, die: 3))
    }

    @Test func theOnlyPawnThatCanMoveWaitsForATap() throws {
        let board = try board([LudoBoard.move(die: 6, choice: .first)])
        #expect(board.legalChoices(die: 3) == [.first])
        #expect(!LudoRollDecision.passesByItself(board: board, die: 3))
    }

    // MARK: Saved roll

    @Test func aRollSavedForThisPositionComesBack() {
        let saved = LudoSavedRoll(position: position, die: 5)
        #expect(LudoRollDecision.restoredDie(from: saved, at: position) == 5)
    }

    @Test func aRollFromAnotherPositionIsDiscarded() {
        let saved = LudoSavedRoll(position: position, die: 5)
        let laterMove = LudoPosition(gameID: position.gameID, gameNumber: 3, moveCount: 5)
        let rematch = LudoPosition(gameID: position.gameID, gameNumber: 4, moveCount: 4)
        let otherGame = LudoPosition(gameID: UUID(), gameNumber: 3, moveCount: 4)
        for other in [laterMove, rematch, otherGame] {
            #expect(LudoRollDecision.restoredDie(from: saved, at: other) == nil)
        }
        #expect(LudoRollDecision.restoredDie(from: nil, at: position) == nil)
    }

    @Test func aSavedRollOutsideTheDiceIsDiscarded() {
        for die in [0, 7, -1] {
            let saved = LudoSavedRoll(position: position, die: die)
            #expect(LudoRollDecision.restoredDie(from: saved, at: position) == nil)
        }
    }

    @Test func aSavedRollSurvivesTheLocalDocumentCoding() throws {
        var document = BoardGamesLocalDocument()
        document.ludoRoll = LudoSavedRoll(position: position, die: 2)
        let data = try PaeoniaConvexClient.encoder.encode(document)
        let decoded = try PaeoniaConvexClient.decoder.decode(BoardGamesLocalDocument.self, from: data)
        #expect(decoded.ludoRoll == document.ludoRoll)
        #expect(BoardGamesLocalDocument().ludoRoll == nil)
    }

    // MARK: Hints

    @Test func theFirstRollOfAGameSaysSwipeTheDie() throws {
        #expect(LudoRollDecision.hintBeforeRoll(board: .initial, moves: [], me: .one) == .swipeToRoll)
        // Player two has not moved yet either.
        let afterPlayerOne = Array(repeating: LudoBoard.move(die: 2, choice: .pass), count: 3)
        let board = try board(afterPlayerOne)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: afterPlayerOne, me: .two) == .swipeToRoll)
    }

    @Test func anotherRollSaysRollAgain() throws {
        let moves = [LudoBoard.move(die: 6, choice: .first)]
        let board = try board(moves)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: moves, me: .one) == .rollAgain)
    }

    @Test func pawnsStillInTheBaseSayRollASix() throws {
        // Both players missed a 6 three times, so player one is back with every pawn in the base.
        let moves = Array(repeating: LudoBoard.move(die: 2, choice: .pass), count: 6)
        let board = try board(moves)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: moves, me: .one) == .rollSix)
    }

    @Test func aMissedSixSaysHowManyTriesAreLeft() throws {
        let one = [LudoBoard.move(die: 2, choice: .pass)]
        #expect(LudoRollDecision.hintBeforeRoll(board: try board(one), moves: one, me: .one) == .triesLeft(2))
        let two = one + [LudoBoard.move(die: 4, choice: .pass)]
        #expect(LudoRollDecision.hintBeforeRoll(board: try board(two), moves: two, me: .one) == .triesLeft(1))
    }

    @Test func aPawnOnTheBoardNeedsNoHint() throws {
        let moves = [
            LudoBoard.move(die: 6, choice: .first),
            LudoBoard.move(die: 4, choice: .first),
            // Player two misses a 6 three times, so the turn comes back to player one.
            LudoBoard.move(die: 2, choice: .pass),
            LudoBoard.move(die: 2, choice: .pass),
            LudoBoard.move(die: 2, choice: .pass),
        ]
        let board = try board(moves)
        #expect(board.next == .one)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: moves, me: .one) == nil)
    }

    @Test func aRollWithNoMoveSaysSoWithTheNumber() {
        #expect(LudoRollDecision.hintAfterRoll(board: .initial, die: 3) == .noMove(die: 3))
        #expect(LudoRollDecision.hintAfterRoll(board: .initial, die: 6) == nil)
    }
}
