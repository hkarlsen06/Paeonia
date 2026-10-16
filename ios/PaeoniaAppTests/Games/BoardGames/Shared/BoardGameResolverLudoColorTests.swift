import Foundation
import Testing
@testable import PaeoniaApp

/// Ludo's piece colors in the phone's picture of a game: a pick travels with a
/// player's first move of the game, and the colors stay through a rematch.
struct BoardGameResolverLudoColorTests {
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

    private func ludoGame(
        first: UUID = Fixture.me,
        moves: [Int] = [],
        finished: Bool = false,
        winner: UUID? = nil
    ) -> RemoteBoardGame {
        Fixture.game(
            kind: .ludo,
            first: first,
            moves: moves,
            finished: finished,
            winner: winner,
            myColor: .pink,
            partnerColor: .lavender
        )
    }

    @Test func aFirstMoveCarriesThePickedColor() throws {
        let game = ludoGame()

        let snapshot = try resolve(game, [.move(Fixture.move(15, on: game, ludoColor: .gold))], as: LudoBoard.self)

        #expect(snapshot.myColor == .gold)
        #expect(snapshot.partnerColor == .lavender)
    }

    @Test func aPickOfThePartnersColorIsIgnored() throws {
        let game = ludoGame()

        let snapshot = try resolve(game, [.move(Fixture.move(15, on: game, ludoColor: .lavender))], as: LudoBoard.self)

        #expect(snapshot.myColor == .pink)
        #expect(snapshot.moves == [15])
    }

    @Test func aPickOnALaterMoveIsIgnored() throws {
        // A 6 keeps the turn, so this is my second move of the game.
        let game = ludoGame(moves: [15])

        let snapshot = try resolve(game, [.move(Fixture.move(15, on: game, ludoColor: .sky))], as: LudoBoard.self)

        #expect(snapshot.myColor == .pink)
        #expect(snapshot.moves == [15, 15])
    }

    @Test func thePartnerStartingDoesNotStopMyFirstMoveFromPicking() throws {
        // The partner missed a 6 three times, each time with a 1, so my first move of the game is their fourth.
        let game = ludoGame(first: partner, moves: [2, 2, 2])

        let snapshot = try resolve(game, [.move(Fixture.move(15, on: game, ludoColor: .sky))], as: LudoBoard.self)

        #expect(snapshot.myColor == .sky)
        #expect(snapshot.partnerColor == .lavender)
    }

    @Test func theColorsStayThroughARematch() throws {
        let win = try LudoFixture.named("playerOneWins")
        let game = Fixture.game(
            kind: .ludo,
            first: me,
            moves: win.moves,
            finished: true,
            winner: me,
            myColor: .gold,
            partnerColor: .sky
        )

        let snapshot = try resolve(game, [.rematch(Fixture.rematch(of: game))], as: LudoBoard.self)

        #expect(snapshot.gameNumber == 2)
        #expect(snapshot.myColor == .gold)
        #expect(snapshot.partnerColor == .sky)
    }

    @Test func otherGamesHaveNoColors() throws {
        let game = Fixture.game()

        let snapshot = try resolve(game, [.move(Fixture.move(3, on: game))], as: ConnectFourBoard.self)

        #expect(snapshot.myColor == nil)
        #expect(snapshot.partnerColor == nil)
    }
}
