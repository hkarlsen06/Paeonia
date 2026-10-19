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
}
