import Foundation
import Testing
@testable import PaeoniaApp

/// How the phone shows a game: the server's game with the unsent actions on top.
struct BoardGameResolverTests {
    private typealias Fixture = BoardGameDataFixture
    private let me = Fixture.me
    private let partner = Fixture.partner

    private func resolve<Board: BoardGameRules>(
        _ game: RemoteBoardGame,
        _ pending: [BoardGamePendingAction],
        as type: Board.Type
    ) throws -> BoardGameSnapshot<Board> {
        try #require(BoardGameResolver.resolve(game, pending: pending, userID: me, partnerID: partner, as: type))
    }

    // MARK: Moves

    @Test func aPendingMoveAppliesWhenItNamesTheGamesVersion() throws {
        let game = Fixture.game()

        let snapshot = try resolve(game, [.move(Fixture.move(3, on: game))], as: ConnectFourBoard.self)

        #expect(snapshot.moves == [3])
        #expect(snapshot.version == 2)
        #expect(snapshot.unsentCount == 1)
        #expect(snapshot.board.next == .two)
    }

    @Test func aMoveTheServerAlreadyHasIsSkipped() throws {
        // The server took the move and answered before the queue let go of it.
        let before = Fixture.game()
        let after = Fixture.game(moves: [3])

        let snapshot = try resolve(after, [.move(Fixture.move(3, on: before))], as: ConnectFourBoard.self)

        #expect(snapshot.moves == [3])
        #expect(snapshot.version == 2)
        #expect(snapshot.unsentCount == 0)
    }

    @Test func aStaleMoveIsSkipped() throws {
        // The partner moved while this phone was offline, so the move was made
        // on a version the game has left. It never reaches the board.
        let game = Fixture.game(first: partner, moves: [3, 4, 2])
        let stale = Fixture.move(5, on: game, expectedVersion: 3)
        let ahead = Fixture.move(5, on: game, expectedVersion: 9)

        let snapshot = try resolve(game, [.move(stale), .move(ahead)], as: ConnectFourBoard.self)

        #expect(snapshot.moves == [3, 4, 2])
        #expect(snapshot.unsentCount == 0)
    }

    @Test func aMoveOutOfTurnOrFromAnotherGameIsSkipped() throws {
        let game = Fixture.game(first: partner)
        let notMyTurn = Fixture.move(3, on: game)
        let otherGame = Fixture.move(3, on: Fixture.game(id: Fixture.otherGameID))

        let snapshot = try resolve(game, [.move(notMyTurn), .move(otherGame)], as: ConnectFourBoard.self)

        #expect(snapshot.moves.isEmpty)
        #expect(snapshot.unsentCount == 0)
    }

    @Test func anActionOfAnotherKindOfGameIsLeftAlone() throws {
        let connectFour = Fixture.game(kind: .connectFour)
        let dotsAndBoxes = Fixture.game(kind: .dotsAndBoxes)

        let snapshot = try resolve(connectFour, [.move(Fixture.move(0, on: dotsAndBoxes))], as: ConnectFourBoard.self)

        #expect(snapshot.moves.isEmpty)
    }

    @Test func twoOfflineDotsAndBoxesMovesInARowChainOnTheExtraTurn() throws {
        // Box 0 has three sides. Line 21 closes it, so the same player moves
        // again and the second queued move names the next version.
        let game = Fixture.game(kind: .dotsAndBoxes, moves: [0, 4, 20, 1])
        let closing = Fixture.move(21, on: game)
        let following = Fixture.move(2, on: game, expectedVersion: game.version + 1)

        let snapshot = try resolve(game, [.move(closing), .move(following)], as: DotsAndBoxesBoard.self)

        #expect(snapshot.moves == [0, 4, 20, 1, 21, 2])
        #expect(snapshot.version == game.version + 2)
        #expect(snapshot.unsentCount == 2)
        #expect(snapshot.board.boxCount(for: .one) == 1)
        #expect(snapshot.board.next == .two)
    }

    @Test func aChainBehindAStaleMoveIsSkippedWhole() throws {
        // The first move is stale, so the game never reaches the version the
        // second move names.
        let game = Fixture.game(kind: .dotsAndBoxes, moves: [0, 4, 20, 1])
        let stale = Fixture.move(21, on: game, expectedVersion: game.version - 1)
        let following = Fixture.move(2, on: game, expectedVersion: game.version + 1)

        let snapshot = try resolve(game, [.move(stale), .move(following)], as: DotsAndBoxesBoard.self)

        #expect(snapshot.moves == [0, 4, 20, 1])
        #expect(snapshot.unsentCount == 0)
    }

    // MARK: Stake

    @Test func theStakeRidesOnTheStartersFirstMove() throws {
        let game = Fixture.game()
        let move = Fixture.move(3, on: game, stake: "Loser makes coffee")

        let snapshot = try resolve(game, [.move(move)], as: ConnectFourBoard.self)

        #expect(snapshot.moves == [3])
        #expect(snapshot.stake == "Loser makes coffee")
    }

    @Test func aStakeOnALaterMoveIsIgnored() throws {
        let game = Fixture.game(moves: [3, 4])
        let move = Fixture.move(2, on: game, stake: "Too late")

        let snapshot = try resolve(game, [.move(move)], as: ConnectFourBoard.self)

        #expect(snapshot.moves == [3, 4, 2])
        #expect(snapshot.stake == nil)
    }

    @Test func theServersStakeStaysWhenAMoveFollows() throws {
        let game = Fixture.game(moves: [3, 4], stake: "Loser makes coffee")

        let snapshot = try resolve(game, [.move(Fixture.move(2, on: game))], as: ConnectFourBoard.self)

        #expect(snapshot.stake == "Loser makes coffee")
    }

    // MARK: Finishing and playing again

    @Test func finishingLocallyCountsTheResult() throws {
        let game = Fixture.game(
            moves: Fixture.connectFourAlmostWon,
            myWins: 2,
            partnerWins: 1,
            draws: 1,
            gamesFinished: 4
        )

        let snapshot = try resolve(game, [.move(Fixture.move(0, on: game))], as: ConnectFourBoard.self)

        #expect(snapshot.isFinished)
        #expect(snapshot.board.outcome?.winner == .one)
        #expect(snapshot.myWins == 3)
        #expect(snapshot.partnerWins == 1)
        #expect(snapshot.draws == 1)
        #expect(snapshot.gamesFinished == 5)
    }

    @Test func aGameTheServerFinishedIsNotCountedAgain() throws {
        let game = Fixture.game(
            moves: Fixture.connectFourWin,
            finished: true,
            winner: me,
            myWins: 3,
            gamesFinished: 3
        )

        let snapshot = try resolve(game, [], as: ConnectFourBoard.self)

        #expect(snapshot.isFinished)
        #expect(snapshot.myWins == 3)
        #expect(snapshot.gamesFinished == 3)
    }

    @Test func aLocalRematchSwapsTheStarterAndKeepsThePreviousGame() throws {
        let game = Fixture.game(
            moves: Fixture.connectFourWin,
            finished: true,
            winner: me,
            myWins: 1,
            gamesFinished: 1
        )

        let snapshot = try resolve(game, [.rematch(Fixture.rematch(of: game))], as: ConnectFourBoard.self)

        #expect(snapshot.gameNumber == 2)
        #expect(snapshot.firstUserID == partner)
        #expect(snapshot.player(for: me) == .two)
        #expect(snapshot.moves.isEmpty)
        #expect(snapshot.board == .initial)
        #expect(snapshot.version == game.version + 1)
        #expect(snapshot.unsentCount == 1)
        let previous = try #require(snapshot.previous)
        #expect(previous.gameNumber == 1)
        #expect(previous.firstUserID == me)
        #expect(previous.moves == Fixture.connectFourWin)
        #expect(previous.winnerUserID == me)
        #expect(snapshot.myWins == 1)
    }

    @Test func aFirstMoveQueuedAfterALocalRematchApplies() throws {
        // The partner started and won the game, so the rematch makes this
        // person the starter, and a first move can follow it offline.
        let game = Fixture.game(first: partner, moves: Fixture.connectFourWin, finished: true, winner: partner)
        let rematch = Fixture.rematch(of: game)
        let firstMove = BoardGameMovePayload(
            kind: .connectFour,
            gameID: game.id,
            gameNumber: game.gameNumber + 1,
            expectedVersion: game.version + 1,
            move: 3,
            stake: "Winner picks the film",
            ludoColor: nil,
            createdAt: Fixture.now
        )

        let snapshot = try resolve(game, [.rematch(rematch), .move(firstMove)], as: ConnectFourBoard.self)

        #expect(snapshot.gameNumber == 2)
        #expect(snapshot.firstUserID == me)
        #expect(snapshot.moves == [3])
        #expect(snapshot.stake == "Winner picks the film")
        #expect(snapshot.version == game.version + 2)
        #expect(snapshot.unsentCount == 2)
        #expect(snapshot.previous?.winnerUserID == partner)
    }

    @Test func aRematchForAGameThatIsStillOnIsSkipped() throws {
        let game = Fixture.game(moves: [3])

        let snapshot = try resolve(game, [.rematch(Fixture.rematch(of: game))], as: ConnectFourBoard.self)

        #expect(snapshot.gameNumber == 1)
        #expect(snapshot.moves == [3])
        #expect(snapshot.unsentCount == 0)
    }

    @Test func theLastMoveAndTheRematchChainOnOnePhone() throws {
        let game = Fixture.game(moves: Fixture.connectFourAlmostWon, myWins: 1, gamesFinished: 1)
        let lastMove = Fixture.move(0, on: game)
        let rematch = Fixture.rematch(of: game, expectedVersion: game.version + 1)

        let snapshot = try resolve(game, [.move(lastMove), .rematch(rematch)], as: ConnectFourBoard.self)

        #expect(snapshot.gameNumber == 2)
        #expect(snapshot.firstUserID == partner)
        #expect(snapshot.myWins == 2)
        #expect(snapshot.gamesFinished == 2)
        #expect(snapshot.previous?.winnerUserID == me)
        #expect(snapshot.previous?.moves == Fixture.connectFourWin)
        #expect(snapshot.unsentCount == 2)
    }

    @Test func aGameThatDoesNotReplayGivesNoSnapshot() {
        let broken = Fixture.game(moves: [0, 0, 0, 0, 0, 0, 0])

        let snapshot = BoardGameResolver.resolve(
            broken,
            pending: [],
            userID: me,
            partnerID: partner,
            as: ConnectFourBoard.self
        )

        #expect(snapshot == nil)
    }
}

// MARK: - Attention

extension BoardGameResolverTests {
    /// The partner's move makes it my move, named by that move. A box I close keeps the
    /// turn and the name, and a move of mine that hands the turn back ends it.
    @Test func thePartnersMoveMakesItMyMoveThroughMyExtraTurns() throws {
        let box = DotsAndBoxesBoard.lines(of: 0)
        func turn(_ moves: [Int]) throws -> String? {
            let game = Fixture.game(kind: .dotsAndBoxes, first: partner, moves: moves)
            return try resolve(game, [], as: DotsAndBoxesBoard.self).attention(userID: me, startedHere: false).turn
        }

        let afterPartner = try turn(Array(box.prefix(3)))
        #expect(afterPartner != nil)
        #expect(try turn(box) == afterPartner)
        #expect(try turn(box + [39]) == nil)
        #expect(try turn(Array(box.prefix(1))) != nil)
        #expect(try turn(Array(box.prefix(1))) != afterPartner)
    }

    /// A game I move first in is a handover only when the partner started it with
    /// "Play again". The first game is always its creator's own.
    @Test func aGameThePartnerStartedForMeIsMyMove() throws {
        let rematch = try resolve(Fixture.game(gameNumber: 2), [], as: ConnectFourBoard.self)
        let created = try resolve(Fixture.game(gameNumber: 1), [], as: ConnectFourBoard.self)

        #expect(rematch.attention(userID: me, startedHere: false).turn != nil)
        #expect(rematch.attention(userID: me, startedHere: true).turn == nil)
        #expect(created.attention(userID: me, startedHere: false).turn == nil)
    }
}
