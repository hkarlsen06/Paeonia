import Testing
@testable import PaeoniaApp

struct LudoBoardTests {
    private func board(_ progress: [Int], next: BoardPlayer = .one) -> LudoBoard {
        LudoBoard(progress: progress, next: next, outcome: nil)
    }

    /// The board after `die` with `choice`.
    private func roll(_ board: LudoBoard, _ die: Int, _ choice: LudoChoice) throws -> LudoBoard {
        try #require(board.applying(LudoBoard.move(die: die, choice: choice)))
    }

    private func transition(_ board: LudoBoard, _ die: Int, _ choice: LudoChoice) throws -> LudoTransition {
        try #require(board.transition(LudoBoard.move(die: die, choice: choice)))
    }

    private func progressOn(_ player: BoardPlayer, square: Int) -> Int {
        (square - LudoBoard.startSquare(of: player) + LudoBoard.trackLength) % LudoBoard.trackLength + 1
    }

    // MARK: Move numbers and squares

    @Test func aMoveIsTheDieMinusOneTimesThreePlusTheChoice() {
        #expect(LudoBoard.move(die: 1, choice: .first) == 0)
        #expect(LudoBoard.move(die: 1, choice: .pass) == 2)
        #expect(LudoBoard.move(die: 2, choice: .first) == 3)
        #expect(LudoBoard.move(die: 6, choice: .first) == 15)
        #expect(LudoBoard.move(die: 6, choice: .pass) == 17)
        #expect(LudoBoard.moveLimit == 18)
    }

    @Test func decodeReadsBackEveryMoveAndRejectsTheRest() throws {
        for move in 0..<18 {
            let decoded = try #require(LudoBoard.decode(move))
            #expect(LudoBoard.move(die: decoded.die, choice: decoded.choice) == move)
        }
        let last = try #require(LudoBoard.decode(17))
        #expect(last.die == 6)
        #expect(last.choice == .pass)
        let middle = try #require(LudoBoard.decode(4))
        #expect(middle.die == 2)
        #expect(middle.choice == .second)
        #expect(LudoBoard.decode(-1) == nil)
        #expect(LudoBoard.decode(18) == nil)
    }

    @Test func startSquaresAreZeroAndTwentySixAndSafeSquaresAreTheStartsAndTheEighthPastEach() {
        #expect(LudoBoard.startSquare(of: .one) == 0)
        #expect(LudoBoard.startSquare(of: .two) == 26)
        #expect(LudoBoard.safeSquares == [0, 8, 13, 21, 26, 34, 39, 47])
    }

    @Test func progressOneToFiftyOneIsTheTrackFromThePlayersStartSquare() {
        #expect(LudoBoard.trackSquare(of: .one, progress: 1) == 0)
        #expect(LudoBoard.trackSquare(of: .one, progress: 51) == 50)
        #expect(LudoBoard.trackSquare(of: .two, progress: 1) == 26)
        #expect(LudoBoard.trackSquare(of: .two, progress: 26) == 51)
        #expect(LudoBoard.trackSquare(of: .two, progress: 27) == 0)
        #expect(LudoBoard.trackSquare(of: .two, progress: 51) == 24)
        for progress in [0, 52, 56, 57] {
            #expect(LudoBoard.trackSquare(of: .one, progress: progress) == nil)
            #expect(LudoBoard.trackSquare(of: .two, progress: progress) == nil)
        }
    }

    @Test func pawnIndexesAreZeroAndOneForPlayerOneAndTwoAndThreeForPlayerTwo() {
        #expect([LudoBoard.pawnIndex(.one, 0), LudoBoard.pawnIndex(.one, 1)] == [0, 1])
        #expect([LudoBoard.pawnIndex(.two, 0), LudoBoard.pawnIndex(.two, 1)] == [2, 3])
    }

    @Test func theEmptyBoardHasAllPawnsInTheirBasesAndPlayerOneMovesFirst() {
        let board = LudoBoard.initial

        #expect(board.progress == [0, 0, 0, 0])
        #expect(board.next == .one)
        #expect(board.outcome == nil)
    }

    // MARK: Leaving the base

    @Test func aPawnInTheBaseMovesOnlyOnASix() {
        for die in 1...5 {
            #expect(!LudoBoard.canMove(progress: 0, die: die))
            #expect(LudoBoard.initial.legalChoices(die: die) == [.pass])
            #expect(!LudoBoard.initial.isLegal(LudoBoard.move(die: die, choice: .first)))
            #expect(!LudoBoard.initial.isLegal(LudoBoard.move(die: die, choice: .second)))
        }
        #expect(LudoBoard.canMove(progress: 0, die: 6))
        #expect(LudoBoard.initial.legalChoices(die: 6) == [.first, .second])
    }

    @Test func aSixPutsThePawnOnItsStartSquareAndRollsAgain() throws {
        let after = try roll(.initial, 6, .second)

        #expect(after.progress == [0, 1, 0, 0])
        #expect(after.next == .one)
        #expect(try roll(board([0, 0, 0, 0], next: .two), 6, .first).progress == [0, 0, 1, 0])
    }

    @Test func aPawnOnTheTrackMovesWhileTheOtherWaitsInTheBase() throws {
        let board = board([5, 0, 0, 0])

        #expect(board.legalChoices(die: 3) == [.first])
        #expect(!board.isLegal(LudoBoard.move(die: 3, choice: .second)))
        #expect(try roll(board, 3, .first).progress == [8, 0, 0, 0])
    }

    @Test func bothChoicesAreLegalWhenBothPawnsCanMove() throws {
        let board = board([5, 9, 0, 0])

        #expect(board.legalChoices(die: 2) == [.first, .second])
        #expect(try roll(board, 2, .second).progress == [5, 11, 0, 0])
    }

    @Test func leavingTheBaseOntoASafeStartSquareNeverCaptures() throws {
        // Player two's progress 27 is square 0, player one's start square.
        let after = try roll(board([0, 0, 27, 0]), 6, .first)

        #expect(after.progress == [1, 0, 27, 0])
    }

    // MARK: Turns and extra rolls

    @Test func aPlainMovePassesTheTurn() throws {
        #expect(try roll(board([5, 0, 0, 0]), 3, .first).next == .two)
        #expect(try roll(board([0, 0, 5, 0], next: .two), 3, .first).next == .one)
    }

    @Test func aSixGivesAnotherRoll() throws {
        let after = try roll(board([5, 0, 0, 0]), 6, .first)

        #expect(after.progress == [11, 0, 0, 0])
        #expect(after.next == .one)
        #expect(try roll(board([0, 0, 5, 0], next: .two), 6, .first).next == .two)
    }

    @Test func aPawnReachingHomeGivesAnotherRollWithoutASix() throws {
        let after = try roll(board([52, 3, 0, 0]), 5, .first)

        #expect(after.progress == [57, 3, 0, 0])
        #expect(after.next == .one)
        #expect(after.outcome == nil)
    }

    @Test func aCaptureGivesAnotherRollWithoutASix() throws {
        #expect(try roll(board([10, 0, 37, 0]), 1, .first).next == .one)
    }

    // MARK: Captures

    @Test func landingOnAPartnerPawnSendsItBackToItsBase() throws {
        // Player one's progress 10 is square 9. Moving 1 lands on square 10, where player two's progress 37 stands.
        #expect(LudoBoard.trackSquare(of: .two, progress: 37) == 10)
        #expect(try roll(board([10, 0, 37, 0]), 1, .first).progress == [11, 0, 0, 0])
    }

    @Test func everyPartnerPawnOnTheSquareGoesBack() throws {
        #expect(try roll(board([10, 0, 37, 37]), 1, .first).progress == [11, 0, 0, 0])
    }

    @Test func partnerPawnsOnOtherSquaresStay() throws {
        #expect(try roll(board([10, 0, 37, 38]), 1, .first).progress == [11, 0, 0, 38])
    }

    @Test func playerTwoCapturesPlayerOneTheSameWay() throws {
        // Player one's progress 30 is square 29. Player two's progress 3 is square 28 and moves 1 onto it.
        #expect(try roll(board([30, 0, 3, 0], next: .two), 1, .first).progress == [0, 0, 4, 0])
    }

    @Test func capturesWorkAcrossTheWrapFromSquare51ToSquare0() throws {
        #expect(LudoBoard.trackSquare(of: .two, progress: 29) == 2)
        #expect(try roll(board([2, 0, 0, 29]), 1, .first).progress == [3, 0, 0, 0])
    }

    @Test func aPawnOnTheLastTrackSquareOfItsLapCanBeCaptured() throws {
        // Player two's progress 51 is square 24, which is player one's progress 25.
        #expect(try roll(board([24, 0, 51, 0]), 1, .first).progress == [25, 0, 0, 0])
    }

    @Test func pawnsOfTheSamePlayerOnASquareDoNotCaptureEachOther() throws {
        #expect(try roll(board([10, 11, 0, 0]), 1, .first).progress == [11, 11, 0, 0])
    }

    @Test func walkingPastAPartnerPawnDoesNotCaptureIt() throws {
        #expect(try roll(board([8, 0, 37, 0]), 4, .first).progress == [12, 0, 37, 0])
    }

    @Test func steppingIntoTheHomeColumnCapturesNothing() throws {
        // Player one's progress 51 is square 50 and player two's progress 26 is square 51. Step 52 leaves the track.
        #expect(try roll(board([51, 0, 26, 0]), 1, .first).progress == [52, 0, 26, 0])
    }

    // MARK: Safe squares

    @Test func landingOnASafeSquareWhereThePartnerStandsSendsNobodyHome() throws {
        // Player two's progress 35 is square 8. Player one's progress 8 is square 7, and 1 more lands on square 8.
        #expect(LudoBoard.trackSquare(of: .two, progress: 35) == 8)
        let after = try roll(board([8, 0, 35, 0]), 1, .first)

        #expect(after.progress == [9, 0, 35, 0])
        #expect(after.next == .two)
    }

    @Test func aStartSquareIsSafeToo() throws {
        let after = try roll(board([26, 0, 1, 0]), 1, .first)

        #expect(after.progress == [27, 0, 1, 0])
        #expect(after.next == .two)
    }

    @Test func everySafeSquareIsSafeForBothPlayers() throws {
        for square in LudoBoard.safeSquares {
            for mover in [BoardPlayer.one, .two] {
                let target = progressOn(mover, square: square)
                // Reaching the mover's own start square from the base is tested above.
                guard target > 1 else { continue }
                let partner = mover.other
                var progress = [0, 0, 0, 0]
                progress[LudoBoard.pawnIndex(mover, 0)] = target - 1
                progress[LudoBoard.pawnIndex(partner, 0)] = progressOn(partner, square: square)

                let after = try roll(board(progress, next: mover), 1, .first)

                #expect(after.progress[LudoBoard.pawnIndex(mover, 0)] == target)
                #expect(after.progress[LudoBoard.pawnIndex(partner, 0)] == progressOn(partner, square: square))
            }
        }
    }

    // MARK: The way home

    @Test func aPawnWalksFiftyOneTrackSquaresThenItsHomeColumnThenHome() throws {
        #expect(try roll(board([50, 0, 0, 0]), 1, .first).progress == [51, 0, 0, 0])
        #expect(try roll(board([51, 0, 0, 0]), 1, .first).progress == [52, 0, 0, 0])
        #expect(try roll(board([51, 0, 0, 0]), 6, .first).progress == [57, 0, 0, 0])
    }

    @Test func theExactNumberReachesHome() throws {
        #expect(try roll(board([52, 0, 0, 0]), 5, .first).progress == [57, 0, 0, 0])
        #expect(try roll(board([56, 0, 0, 0]), 1, .first).progress == [57, 0, 0, 0])
    }

    @Test func aRollPastHomeIsIllegalForThatPawn() {
        #expect(!board([52, 3, 0, 0]).isLegal(LudoBoard.move(die: 6, choice: .first)))
        #expect(!board([56, 3, 0, 0]).isLegal(LudoBoard.move(die: 2, choice: .first)))
        #expect(LudoBoard.canMove(progress: 52, die: 5))
        #expect(!LudoBoard.canMove(progress: 52, die: 6))
        #expect(!LudoBoard.canMove(progress: 57, die: 1))
    }

    @Test func theOtherPawnCanTakeARollTheFirstCant() throws {
        let board = board([56, 3, 0, 0])

        #expect(board.legalChoices(die: 2) == [.second])
        #expect(try roll(board, 2, .second).progress == [56, 5, 0, 0])
    }

    @Test func aPawnAtHomeNeverMovesAgain() {
        let board = board([57, 3, 0, 0])

        #expect(board.legalChoices(die: 4) == [.second])
        #expect(!board.isLegal(LudoBoard.move(die: 4, choice: .first)))
    }

    // MARK: Passing

    @Test func aPassIsTheOnlyChoiceWhenNoPawnCanMove() {
        #expect(board([0, 0, 0, 0]).legalChoices(die: 3) == [.pass])
        #expect(board([56, 57, 0, 0]).legalChoices(die: 2) == [.pass])
    }

    @Test func aPassChangesNothingButTheTurn() throws {
        let after = try roll(.initial, 3, .pass)

        #expect(after == LudoBoard(progress: [0, 0, 0, 0], next: .two, outcome: nil))
    }

    @Test func aPassOnASixGivesAnotherRoll() throws {
        // Both pawns are close to home, so a 6 moves neither.
        let board = board([56, 57, 0, 0])

        #expect(board.legalChoices(die: 6) == [.pass])
        let after = try roll(board, 6, .pass)
        #expect(after.progress == [56, 57, 0, 0])
        #expect(after.next == .one)
    }

    @Test func aPassIsIllegalWhileAPawnCouldMove() {
        #expect(!LudoBoard.initial.isLegal(LudoBoard.move(die: 6, choice: .pass)))
        #expect(!board([5, 0, 0, 0]).isLegal(LudoBoard.move(die: 1, choice: .pass)))
        #expect(!board([56, 57, 0, 0]).isLegal(LudoBoard.move(die: 1, choice: .pass)))
        #expect(board([56, 57, 0, 0]).isLegal(LudoBoard.move(die: 2, choice: .pass)))
    }

    // MARK: Winning

    @Test func theFirstPlayerWithBothPawnsHomeWinsWithAnEmptyLine() throws {
        let after = try roll(board([57, 56, 12, 0]), 1, .second)

        #expect(after.progress == [57, 57, 12, 0])
        #expect(after.outcome == BoardOutcome(winner: .one, line: []))
    }

    @Test func playerTwoCanWinToo() throws {
        let after = try roll(board([30, 0, 51, 57], next: .two), 6, .first)

        #expect(after.outcome == BoardOutcome(winner: .two, line: []))
    }

    @Test func aPawnStillOnTheWayKeepsTheGameGoing() throws {
        #expect(try roll(board([52, 51, 0, 0]), 5, .first).outcome == nil)
        #expect(try roll(board([57, 52, 0, 0]), 5, .second).outcome == BoardOutcome(winner: .one, line: []))
    }

    @Test func noMoveIsLegalOnceTheGameIsOver() throws {
        let done = try roll(board([57, 56, 12, 0]), 1, .second)

        #expect((0..<LudoBoard.moveLimit).allSatisfy { !done.isLegal($0) })
        #expect((1...6).allSatisfy { done.legalChoices(die: $0).isEmpty })
        #expect(done.transition(0) == nil)
    }

    @Test func aMoveAfterTheWinningMoveMakesTheWholeListIllegal() throws {
        #expect(LudoBoard.replay(try LudoFixture.named("playerOneWins").moves + [0]) == nil)
        #expect(LudoBoard.replay(try LudoFixture.named("playerTwoWins").moves + [17]) == nil)
    }

    // MARK: Illegal moves

    @Test func anythingThatIsNotAMoveIntegerIsRejected() {
        for bad in [-1, 18, 100, Int.max, Int.min] {
            #expect(LudoBoard.initial.applying(bad) == nil)
            #expect(LudoBoard.initial.transition(bad) == nil)
        }
    }

    @Test func aPawnThatCantMoveByTheDieIsRejected() {
        #expect(!LudoBoard.initial.isLegal(LudoBoard.move(die: 5, choice: .first)))
        #expect(!board([57, 57, 0, 0]).isLegal(LudoBoard.move(die: 1, choice: .first)))
    }
}
