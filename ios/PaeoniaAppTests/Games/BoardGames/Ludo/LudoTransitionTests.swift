import Testing
@testable import PaeoniaApp

struct LudoTransitionTests {
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

    // MARK: Squares

    @Test func squareOfPawnReadsBaseTrackHomeColumnAndHome() {
        let board = board([0, 1, 30, 54])

        #expect(board.square(ofPawn: 0) == .base(.one, slot: 0))
        #expect(board.square(ofPawn: 1) == .track(0))
        #expect(board.square(ofPawn: 2) == .track(3))
        #expect(board.square(ofPawn: 3) == .homeColumn(.two, step: 3))
        #expect(self.board([52, 57, 0, 0]).square(ofPawn: 0) == .homeColumn(.one, step: 1))
        #expect(self.board([52, 57, 0, 0]).square(ofPawn: 1) == .home(.one))
        #expect(self.board([0, 0, 0, 56]).square(ofPawn: 3) == .homeColumn(.two, step: 5))
        #expect(self.board([0, 0, 0, 0]).square(ofPawn: 3) == .base(.two, slot: 1))
    }

    // MARK: Transitions

    @Test func exitingTheBaseIsOneHopOntoTheStartSquare() throws {
        let move = try transition(.initial, 6, .second)

        #expect(move == LudoTransition(
            player: .one,
            die: 6,
            choice: .second,
            pawn: 1,
            path: [.track(0)],
            sentHome: [],
            rollsAgain: true
        ))
        #expect(try transition(.initial, 6, .first).path == [.track(0)])
        #expect(try transition(board([0, 0, 0, 0], next: .two), 6, .first).path == [.track(26)])
    }

    @Test func aWalkListsEverySquareItStepsOnTheLastOneIncluded() throws {
        let move = try transition(board([5, 0, 0, 0]), 3, .first)

        #expect(move.pawn == 0)
        #expect(move.path == [.track(5), .track(6), .track(7)])
        #expect(move.sentHome.isEmpty)
        #expect(!move.rollsAgain)
    }

    @Test func aWalkWrapsAroundTheEndOfTheTrack() throws {
        // Player two's progress 24 is square 49. Four more steps are squares 50, 51, 0 and 1.
        let move = try transition(board([0, 0, 24, 0], next: .two), 4, .first)

        #expect(move.pawn == 2)
        #expect(move.path == [.track(50), .track(51), .track(0), .track(1)])
    }

    @Test func aWalkIntoTheHomeColumnLeavesTheTrack() throws {
        let move = try transition(board([49, 0, 0, 0]), 5, .first)

        #expect(move.path == [
            .track(49), .track(50), .homeColumn(.one, step: 1), .homeColumn(.one, step: 2), .homeColumn(.one, step: 3)
        ])
    }

    @Test func reachingHomeEndsThePathAtHomeAndRollsAgain() throws {
        let move = try transition(board([54, 3, 0, 0]), 3, .first)

        #expect(move.path == [.homeColumn(.one, step: 4), .homeColumn(.one, step: 5), .home(.one)])
        #expect(move.rollsAgain)
    }

    @Test func aCaptureListsEverySentHomePawnAndRollsAgain() throws {
        let one = try transition(board([10, 0, 37, 38]), 1, .first)
        #expect(one.sentHome == [2])
        #expect(one.rollsAgain)

        let both = try transition(board([10, 0, 37, 37]), 1, .first)
        #expect(both.sentHome == [2, 3])

        let byPlayerTwo = try transition(board([30, 0, 3, 0], next: .two), 1, .first)
        #expect(byPlayerTwo.player == .two)
        #expect(byPlayerTwo.pawn == 2)
        #expect(byPlayerTwo.sentHome == [0])
    }

    @Test func aSafeSquareSendsNobodyHome() throws {
        #expect(try transition(board([8, 0, 35, 0]), 1, .first).sentHome.isEmpty)
    }

    @Test func aPassHasNoPawnNoPathAndRollsAgainOnlyOnASix() throws {
        let plain = try transition(.initial, 3, .pass)
        #expect(plain == LudoTransition(
            player: .one,
            die: 3,
            choice: .pass,
            pawn: nil,
            path: [],
            sentHome: [],
            rollsAgain: false
        ))

        let six = try transition(board([56, 57, 0, 0]), 6, .pass)
        #expect(six.pawn == nil)
        #expect(six.path.isEmpty)
        #expect(six.rollsAgain)
    }

    @Test func theWinningMoveDoesNotRollAgain() throws {
        let move = try transition(board([57, 56, 12, 0]), 1, .second)

        #expect(move.path == [.home(.one)])
        #expect(!move.rollsAgain)
    }

    // MARK: Fixture games

    @Test func fixtureGamesReplayToTheSameBoardAsTheServer() throws {
        for fixture in LudoFixture.all {
            let board = try #require(LudoBoard.replay(fixture.moves), "\(fixture.name) has an illegal move")

            #expect(board.progress == fixture.progress, "\(fixture.name) progress")
            #expect(board.next == fixture.next, "\(fixture.name) next")
            #expect(board.outcome?.winner == fixture.winner, "\(fixture.name) winner")
            #expect(board.outcome == nil || board.outcome?.line == [], "\(fixture.name) line")
        }
    }

    @Test func theCaptureFixtureSendsPlayerTwosPawnHomeOnTheLastMoveOnly() throws {
        let moves = try LudoFixture.named("capture").moves

        #expect(LudoBoard.replay(Array(moves.dropLast()))?.progress == [28, 0, 3, 0])
        #expect(LudoBoard.replay(moves)?.progress == [29, 0, 0, 0])
    }

    @Test func theSafeSquareFixtureLeavesPlayerTwosPawnOnSquare26() throws {
        let moves = try LudoFixture.named("safeSquare").moves

        #expect(LudoBoard.replay(Array(moves.dropLast()))?.progress == [26, 0, 3, 1])
    }

    @Test func theWholeGamesFinishOnTheLastMoveOnly() throws {
        for fixture in LudoFixture.all where fixture.winner != nil {
            #expect(LudoBoard.replay(Array(fixture.moves.dropLast()))?.outcome == nil, "\(fixture.name)")
        }
    }

    @Test func transitionsAlongAWholeGameMatchTheBoardsTheyProduce() throws {
        for fixture in LudoFixture.all {
            var board = LudoBoard.initial
            for move in fixture.moves {
                let transition = try #require(board.transition(move), "\(fixture.name) move \(move)")
                let after = try #require(board.applying(move))

                #expect(transition.player == board.next)
                if let pawn = transition.pawn {
                    #expect(after.square(ofPawn: pawn) == transition.path.last)
                } else {
                    #expect(after.progress == board.progress)
                }
                for sent in transition.sentHome {
                    #expect(after.progress[sent] == 0)
                    #expect(board.progress[sent] > 0)
                }
                if after.outcome == nil {
                    #expect((after.next == board.next) == transition.rollsAgain, "\(fixture.name) move \(move)")
                }
                board = after
            }
        }
    }

    @Test func randomGamesAlwaysEndWithAWinnerAndNoDraws() {
        let finished = playRandomGames(LudoBoard.self, maxMoves: 3_000)

        #expect(finished.allSatisfy { $0.outcome?.winner != nil })
    }
}
