import Testing
@testable import PaeoniaApp

struct LudoTransitionTests {
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
