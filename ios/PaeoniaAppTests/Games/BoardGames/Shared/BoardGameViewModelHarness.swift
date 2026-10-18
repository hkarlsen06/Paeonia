import Foundation
import Testing
@testable import PaeoniaApp

typealias ConnectFourViewModel = BoardGameViewModel<ConnectFourBoard>

/// One of the two partners in a test game.
enum BoardGameSide {
    case me
    case partner
}

/// Stands in for the view model's clock. A wait of a minute or more (the presence
/// heartbeat and the clock tick) really sleeps, so those loops never spin. Every
/// shorter wait returns at once and is recorded. With Reduce Motion on, the board
/// waits once after each move it shows, so `waits.count` is the number of moves
/// the board replayed or played.
final class BoardGameSleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    var waits: [Duration] { lock.withLock { recorded } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            if duration >= .seconds(60) {
                try await Task.sleep(for: duration)
                return
            }
            lock.withLock { recorded.append(duration) }
            await Task.yield()
        }
    }
}

/// A Connect Four screen on in-memory parts. Each harness has its own signed-in
/// person, so a write another test posts to the local store never reloads this
/// view model in the middle of a move.
@MainActor
struct BoardGameHarness {
    typealias Fixture = BoardGameDataFixture

    let me = UUID()
    let partner = Fixture.partner
    let env = GamesTestEnvironment(state: nil)
    let gateway = ScriptedBoardGamesGateway()
    let cache = InMemoryBoardGamesCache()
    let sleeps = BoardGameSleepRecorder()

    // MARK: Games

    func id(of side: BoardGameSide) -> UUID {
        side == .me ? me : partner
    }

    /// The game as the server shows it to me. A game whose moves end the board is
    /// finished, and player one (the starter) is its winner.
    func game(
        first: BoardGameSide = .me,
        moves: [Int] = [],
        stake: String? = nil,
        myWins: Int = 0,
        partnerWins: Int = 0,
        draws: Int = 0,
        gamesFinished: Int = 0
    ) -> RemoteBoardGame {
        let starter = id(of: first)
        let second = id(of: first == .me ? .partner : .me)
        let outcome = ConnectFourBoard.replay(moves)?.outcome
        return Fixture.game(
            first: starter,
            moves: moves,
            finished: outcome != nil,
            winner: outcome?.winner.map { $0 == .one ? starter : second },
            stake: stake,
            myWins: myWins,
            partnerWins: partnerWins,
            draws: draws,
            gamesFinished: gamesFinished
        )
    }

    /// The next game after `finished`, as a rematch makes it: the other partner
    /// starts, and `previous` keeps the ending.
    func game(after finished: RemoteBoardGame) -> RemoteBoardGame {
        let starter = finished.firstUserID == me ? partner : me
        return RemoteBoardGame(
            id: finished.id,
            kind: finished.kind,
            gameNumber: finished.gameNumber + 1,
            status: .playing,
            version: finished.version + 1,
            firstUserID: starter,
            moves: [],
            turnUserID: starter,
            winnerUserID: nil,
            winLine: [],
            stake: nil,
            stakeByUserID: nil,
            myColor: finished.myColor,
            partnerColor: finished.partnerColor,
            photoMediaAssetID: nil,
            myWins: finished.myWins,
            partnerWins: finished.partnerWins,
            draws: finished.draws,
            gamesFinished: finished.gamesFinished,
            previous: RemoteBoardGameEnding(
                gameNumber: finished.gameNumber,
                firstUserID: finished.firstUserID,
                moves: finished.moves,
                winnerUserID: finished.winnerUserID,
                winLine: finished.winLine,
                stake: finished.stake,
                photoMediaAssetID: finished.photoMediaAssetID,
                finishedAt: Fixture.now
            ),
            startedAt: Fixture.now,
            finishedAt: nil,
            turnStartedAt: Fixture.now,
            updatedAt: Fixture.now
        )
    }

    func state(_ games: RemoteBoardGame...) -> RemoteBoardGames {
        RemoteBoardGames(userID: me, partnerUserID: partner, coupleID: Fixture.coupleID, dataEpoch: "", games: games)
    }

    // MARK: Cache

    /// What the live feed does when the server's game changes. A view model that
    /// is open picks it up on its next `reload()`.
    func save(_ game: RemoteBoardGame) async {
        await cache.saveState(state(game), ownerUserID: me)
    }

    func setPlayStyle(_ playStyle: GamePlayStyle) async {
        let settings = RemoteGameSettings(
            coupleID: Fixture.coupleID,
            playStyle: playStyle,
            language: .en,
            updatedByUserID: me,
            createdAt: Fixture.now,
            updatedAt: Fixture.now
        )
        let overview = RemoteGamesOverview(
            userID: me,
            partnerUserID: partner,
            coupleID: Fixture.coupleID,
            settings: settings,
            presence: []
        )
        await env.cache.saveOverview(overview, ownerUserID: me)
    }

    /// How far this phone showed a game.
    func position(_ moveCount: Int, game gameNumber: Int = 1) -> BoardGameShownPosition {
        BoardGameShownPosition(gameNumber: gameNumber, moveCount: moveCount)
    }

    func shownPosition() async -> BoardGameShownPosition? {
        await cache.document(ownerUserID: me).shown[GameKind.connectFour.rawValue]
    }

    /// The view model writes how far it showed the game in a task of its own, so
    /// this waits for the cache to hold `gameNumber` and `moveCount`.
    func expectShown(
        game gameNumber: Int,
        moves moveCount: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let expected = BoardGameShownPosition(gameNumber: gameNumber, moveCount: moveCount)
        let deadline = ContinuousClock.now + .seconds(2)
        while await shownPosition() != expected, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await shownPosition() == expected, sourceLocation: sourceLocation)
    }

    /// A view model that never ran has nothing to remember. Gives a stray write a
    /// moment to land before it checks.
    func expectNothingShown(sourceLocation: SourceLocation = #_sourceLocation) async {
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await shownPosition() == nil, sourceLocation: sourceLocation)
    }

    // MARK: Queue

    func queuedMoves() async -> [BoardGameMovePayload] {
        await queued(.boardGameMove)
    }

    func queuedRematches() async -> [BoardGameRematchPayload] {
        await queued(.boardGameRematch)
    }

    private func queued<Payload: Decodable>(_ kind: SyncPendingOperationKind) async -> [Payload] {
        let operations = (try? await env.pending.inFlightOperations(ownerUserID: me, kind: kind)) ?? []
        return operations.compactMap { operation in
            operation.requestData.flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        }
    }

    /// The server refused the queued moves for good, so the queue lets go of them.
    func refuseQueuedMoves() async throws {
        let operations = try await env.pending.inFlightOperations(ownerUserID: me, kind: .boardGameMove)
        for operation in operations {
            try await env.pending.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: "that move is not allowed",
                at: Fixture.now
            )
        }
    }

    // MARK: View model

    /// `partnerTiming` of a minute or more holds the board inside a partner's
    /// move animation (see `BoardGameSleepRecorder`).
    func makeViewModel(
        partnerTiming: Duration = .zero,
        mineTiming: Duration = .zero,
        openLeadIn: Duration = .zero
    ) -> ConnectFourViewModel {
        var dependencies = env.dependencies()
        dependencies.boardGamesGateway = gateway
        dependencies.boardGamesCache = cache
        let viewModel = ConnectFourViewModel(
            kind: .connectFour,
            timing: BoardGameMoveTiming(mine: mineTiming, partner: partnerTiming, openLeadIn: openLeadIn),
            dependencies: dependencies,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600),
            sleep: sleeps.sleep
        )
        viewModel.configure(
            participants: GameParticipants(
                currentUserID: me,
                coupleID: Fixture.coupleID,
                partnerName: "Robin",
                currentName: "Alex"
            )
        )
        return viewModel
    }

    /// Opens the screen the way the app does and waits until the board has
    /// caught up with the game. `shown` is how far this phone showed the game
    /// before.
    func openBoard(
        _ game: RemoteBoardGame,
        shown: BoardGameShownPosition? = nil,
        reducedMotion: Bool = true
    ) async -> ConnectFourViewModel {
        await save(game)
        if let shown {
            await cache.markShown(shown, kind: .connectFour, ownerUserID: me)
        }
        return await reopenBoard(reducedMotion: reducedMotion)
    }

    /// Opens a new screen on whatever the cache holds now.
    func reopenBoard(reducedMotion: Bool = true) async -> ConnectFourViewModel {
        let viewModel = makeViewModel()
        await viewModel.start(prefersReducedMotion: reducedMotion)
        let caughtUp = await waitUntil { !viewModel.isReplaying }
        #expect(caughtUp)
        return viewModel
    }
}
