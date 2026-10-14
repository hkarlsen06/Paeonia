import Foundation
import Testing
@testable import PaeoniaApp

struct LudoRollDecisionTests {
    private func board(_ moves: [Int]) throws -> LudoBoard {
        try #require(LudoBoard.replay(moves))
    }

    private let position = LudoPosition(gameID: UUID(), gameNumber: 3, moveCount: 4)

    // MARK: Distinct choices

    @Test func twoPawnsInTheBaseCountAsOneChoice() throws {
        let start = LudoBoard.initial
        #expect(start.legalChoices(die: 6) == [.first, .second])
        #expect(LudoRollDecision.distinctChoices(board: start, die: 6) == [.first])
    }

    @Test func twoPawnsOnOneSquareCountAsOneChoice() throws {
        // Both pawns came out on the start square.
        let stacked = try board([LudoBoard.move(die: 6, choice: .first), LudoBoard.move(die: 6, choice: .second)])
        #expect(stacked.legalChoices(die: 3) == [.first, .second])
        #expect(LudoRollDecision.distinctChoices(board: stacked, die: 3) == [.first])
    }

    @Test func pawnsOnDifferentSquaresAreTwoChoices() throws {
        let board = try board([LudoBoard.move(die: 6, choice: .first)])
        // The first pawn is out and the second is in the base, and a 6 moves either one.
        #expect(LudoRollDecision.distinctChoices(board: board, die: 6) == [.first, .second])
    }

    @Test func aPawnThatCannotMoveIsNotAChoice() throws {
        let board = try board([LudoBoard.move(die: 6, choice: .first)])
        #expect(LudoRollDecision.distinctChoices(board: board, die: 3) == [.first])
    }

    @Test func withNoPawnToMoveThePassIsTheOnlyChoice() {
        #expect(LudoRollDecision.distinctChoices(board: .initial, die: 3) == [.pass])
    }

    // MARK: Moving by itself

    @Test func theOnlyOptionMovesAfterHalfASecond() throws {
        let board = try board([LudoBoard.move(die: 6, choice: .first)])
        #expect(LudoRollDecision.automaticMove(board: board, die: 3) == .move(.first, after: .milliseconds(500)))
        // Two pawns in the base come out as one option.
        #expect(LudoRollDecision.automaticMove(board: .initial, die: 6) == .move(.first, after: .milliseconds(500)))
    }

    @Test func aPassMovesAfterOnePointTwoSeconds() {
        #expect(LudoRollDecision.automaticMove(board: .initial, die: 3) == .pass(after: .milliseconds(1_200)))
    }

    @Test func twoDifferentOptionsWaitForThePerson() throws {
        let board = try board([LudoBoard.move(die: 6, choice: .first)])
        #expect(LudoRollDecision.automaticMove(board: board, die: 6) == nil)
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

    @Test func theFirstRollOfAGameSaysTapTheDie() throws {
        #expect(LudoRollDecision.hintBeforeRoll(board: .initial, moves: [], me: .one) == .tapToRoll)
        // Player two has not moved yet either.
        let afterPlayerOne = [LudoBoard.move(die: 2, choice: .pass)]
        let board = try board(afterPlayerOne)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: afterPlayerOne, me: .two) == .tapToRoll)
    }

    @Test func anotherRollSaysRollAgain() throws {
        let moves = [LudoBoard.move(die: 6, choice: .first)]
        let board = try board(moves)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: moves, me: .one) == .rollAgain)
    }

    @Test func pawnsStillInTheBaseSayRollASix() throws {
        // Both players passed once, so player one is back with every pawn in the base.
        let moves = [LudoBoard.move(die: 2, choice: .pass), LudoBoard.move(die: 3, choice: .pass)]
        let board = try board(moves)
        #expect(LudoRollDecision.hintBeforeRoll(board: board, moves: moves, me: .one) == .rollSix)
    }

    @Test func aPawnOnTheBoardNeedsNoHint() throws {
        let moves = [
            LudoBoard.move(die: 6, choice: .first),
            LudoBoard.move(die: 4, choice: .first),
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
