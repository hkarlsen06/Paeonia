import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

/// The board game developer scenarios hold legal games, and each one opens in
/// the state its title promises.
@MainActor
struct BoardGameScenarioFixturesTests {
    private typealias Fixture = DeveloperBoardGamesFixture
    private let me = DeveloperGamesFixture.me
    private let partner = DeveloperGamesFixture.partner

    /// Every scenario id the board games add, the hub one last.
    private static let scenarioIDs = [
        "connect-four-your-turn", "connect-four-partner-turn", "connect-four-partner-move",
        "connect-four-won", "connect-four-first-move", "connect-four-missed-ending", "connect-four-offline",
        "dots-and-boxes-photo", "dots-and-boxes-extra-turn", "dots-and-boxes-won-photo", "dots-and-boxes-plain",
        "ultimate-tic-tac-toe-forced", "ultimate-tic-tac-toe-free", "ultimate-tic-tac-toe-partner-move",
        "ultimate-tic-tac-toe-won", "board-game-mark-editor", "games-hub-board-games",
    ]

    private var scenariosWithGames: [DeveloperScenario] {
        DeveloperScenario.allCases.filter { !Fixture.setups(for: $0).isEmpty }
    }

    private func firstSetup(_ scenario: DeveloperScenario) throws -> DeveloperBoardGameSetup {
        try #require(Fixture.setups(for: scenario).first)
    }

    /// The view model the scenario screen builds, after it read the seeded cache.
    private func openedModel<Board: BoardGameRules>(
        _: Board.Type,
        kind: GameKind,
        scenario: DeveloperScenario
    ) async -> BoardGameViewModel<Board> {
        let dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
        await DeveloperBoardGamesScenarioFactory.seed(scenario, dependencies: dependencies)
        let model = BoardGameViewModel<Board>(
            kind: kind,
            timing: BoardGameMoveTiming(mine: .zero, partner: .zero),
            dependencies: dependencies,
            sleep: { _ in }
        )
        model.configure(participants: DeveloperGamesFixture.participants)
        // The scenario screen is open, and the board moves only while it is.
        // Reduce Motion settles an outcome at once, so the tests read the result.
        model.isRunning = true
        model.prefersReducedMotion = true
        await model.reload()
        // The board replays what this phone has not shown yet, then settles.
        _ = await waitUntil { !model.isReplaying }
        return model
    }

    // MARK: Catalog

    @Test func everyBoardGameScenarioIDIsInTheGamesCatalog() throws {
        for id in Self.scenarioIDs {
            let scenario = try #require(DeveloperScenario(rawValue: id), "\(id)")
            #expect(scenario.category == .games, "\(id)")
        }
        // The hub opens the Games tab. The others open one game.
        let screens = DeveloperScenario.allCases.filter { $0.boardGame != nil }
        #expect(screens.count == Self.scenarioIDs.count - 1)
        #expect(DeveloperScenario.gamesHubBoardGames.boardGame == nil)
    }

    // MARK: Legal games

    @Test func everyScenarioGameReplaysLegallyUnderTheRealRules() {
        #expect(scenariosWithGames.count == Self.scenarioIDs.count)
        for scenario in scenariosWithGames {
            for setup in Fixture.setups(for: scenario) {
                #expect(setup.replayed(setup.moves) != nil, "\(scenario.rawValue)")
                if let queued = setup.queuedMove {
                    #expect(setup.replayed(setup.moves + [queued]) != nil, "\(scenario.rawValue) queued move")
                }
                if let previous = setup.previous {
                    #expect(setup.replayed(previous.moves)?.outcome != nil, "\(scenario.rawValue) previous game")
                }
            }
        }
    }

    @Test func theServerGameAgreesWithTheRulesOnTurnAndOutcome() throws {
        for scenario in scenariosWithGames {
            for setup in Fixture.setups(for: scenario) {
                let game = setup.remoteGame()
                let replayed = try #require(setup.replayed(setup.moves), "\(scenario.rawValue)")
                #expect(game.kind == setup.kind)
                if let outcome = replayed.outcome {
                    #expect(game.status == .finished, "\(scenario.rawValue)")
                    #expect(game.turnUserID == nil, "\(scenario.rawValue)")
                    #expect(game.winLine == outcome.line, "\(scenario.rawValue)")
                    #expect(game.winnerUserID == outcome.winner.map(setup.user), "\(scenario.rawValue)")
                } else {
                    #expect(game.status == .playing, "\(scenario.rawValue)")
                    #expect(game.turnUserID == setup.user(replayed.next), "\(scenario.rawValue)")
                }
            }
        }
    }

    // MARK: Connect Four

    @Test func connectFourYourTurnIsMidGameWithAStakeAndTheInitialsAsMarks() async throws {
        let setup = try firstSetup(.connectFourYourTurn)
        let game = setup.remoteGame()
        #expect(game.turnUserID == me)
        #expect(game.firstUserID == me)
        #expect(game.moves.count == 10)
        #expect(game.stake == "Loser makes coffee")
        #expect(setup.partnerIsHere)
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: 10))
        #expect(Fixture.boardGames(for: .connectFourYourTurn).game(.connectFour) == game)

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourYourTurn)
        #expect(model.phase == .game)
        #expect(model.turnLabel == .yourTurn)
        #expect(model.stakeState == .fixed("Loser makes coffee"))
        #expect(model.partnerStatus == .here)
        #expect(model.invite == .hidden)
        #expect(model.canPlay)
        #expect(!model.hasDrawnMark)
    }

    @Test func connectFourPartnerTurnHasRobinAwayAndTheInviteButton() async throws {
        let setup = try firstSetup(.connectFourPartnerTurn)
        #expect(setup.remoteGame().turnUserID == partner)
        #expect(!setup.partnerIsHere)

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourPartnerTurn)
        #expect(model.turnLabel == .partnerTurn)
        #expect(model.partnerStatus == .away)
        #expect(model.invite == .available)
        #expect(!model.canPlay)
    }

    @Test func connectFourPartnerMoveOpensOneDiscBehindRobinsLastMove() async throws {
        let setup = try firstSetup(.connectFourPartnerMove)
        #expect(setup.remoteGame().turnUserID == me)
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: 9))
        let movers = try #require(ConnectFourBoard.movers(setup.moves))
        #expect(movers.last.map(setup.user) == partner)

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourPartnerMove)
        // Robin's last disc replays, then it is my turn.
        #expect(model.displayedMoves == setup.moves)
        #expect(model.lastMove?.isMine == false)
        #expect(model.lastMove?.number == setup.moves.count)
        #expect(model.canPlay)
    }

    @Test func connectFourWonEndsOnMyDiagonalWithTheLastDiscStillToShow() async throws {
        let setup = try firstSetup(.connectFourWon)
        let game = setup.remoteGame()
        #expect(game.status == .finished)
        #expect(game.winnerUserID == me)
        #expect(game.winLine == [17, 23, 29, 35])
        #expect(game.stake != nil)
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: 10))

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourWon)
        // The winning disc replays, then the result shows.
        #expect(model.displayedMoves == setup.moves)
        #expect(model.lastMove?.number == setup.moves.count)
        #expect(model.showsOutcome)
        #expect(model.result?.winner == .me)
        #expect(model.summary?.status == .youWon)
    }

    @Test func connectFourFirstMoveIsAFreshGameIStartWithAStakeToWrite() async throws {
        let setup = try firstSetup(.connectFourFirstMove)
        let game = setup.remoteGame()
        #expect(game.moves.isEmpty)
        #expect(game.firstUserID == me)
        #expect(game.turnUserID == me)
        #expect(game.stake == nil)

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourFirstMove)
        #expect(model.stakeState == .writable)
        #expect(model.canPlay)
    }

    @Test func connectFourMissedEndingShowsRobinsWinBeforeTheNewGame() async throws {
        let setup = try firstSetup(.connectFourMissedEnding)
        let game = setup.remoteGame()
        let previous = try #require(game.previous)
        #expect(previous.winnerUserID == partner)
        #expect(previous.gameNumber == 9)
        #expect(game.gameNumber == 10)
        // Robin did not start game 9, so I did not start game 10.
        #expect(game.firstUserID == partner)
        #expect(game.turnUserID == me)
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: previous.moves.count - 1))

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourMissedEnding)
        // Robin's winning disc replays on game 9 before the new game.
        #expect(model.isShowingMissedEnding)
        #expect(model.displayedGameNumber == 9)
        #expect(model.displayedMoves == previous.moves)
        #expect(model.result?.isMissedEnding == true)
    }

    @Test func connectFourOfflineKeepsMyMoveInTheQueueAfterAFailedTry() async throws {
        let setup = try firstSetup(.connectFourOffline)
        let game = setup.remoteGame()
        let payload = try #require(setup.queuedPayload())
        let snapshot = try #require(BoardGameResolver.resolve(
            game,
            pending: [.move(payload)],
            userID: me,
            partnerID: partner,
            as: ConnectFourBoard.self
        ))
        #expect(snapshot.unsentCount == 1)
        #expect(snapshot.moves == game.moves + [payload.move])

        let model = await openedModel(ConnectFourBoard.self, kind: .connectFour, scenario: .connectFourOffline)
        #expect(model.isWaitingToSend)
        // A lost connection, not a refusal, so the line says "Saved on this phone".
        #expect(!model.failedWhileOnline)
        #expect(model.turnLabel == .partnerTurn)
    }

    // MARK: Mark editor and the hub

    @Test func theMarkEditorScenarioPlaysTheSameGameAsConnectFourYourTurn() throws {
        #expect(try firstSetup(.boardGameMarkEditor).moves == firstSetup(.connectFourYourTurn).moves)
        #expect(DeveloperScenario.boardGameMarkEditor.boardGame == .connectFour)
    }

    @Test func theHubScenarioShowsTheThreeGamesInDifferentStates() async throws {
        let scenario = DeveloperScenario.gamesHubBoardGames
        let setups = Fixture.setups(for: scenario)
        #expect(setups.map(\.game) == [.connectFour, .dotsAndBoxes, .ultimateTicTacToe])

        let viewModel = DeveloperGamesScenarioFactory.gamesViewModel(for: scenario)
        viewModel.configure(participants: DeveloperGamesFixture.participants)
        await viewModel.reload()

        #expect(viewModel.screen == .hub)
        #expect(viewModel.connectFour.game.summary?.status == .yourTurn)
        #expect(viewModel.dotsAndBoxes.game.summary?.status == .partnerTurn)
        #expect(viewModel.ultimateTicTacToe.game.summary?.status == .partnerWon)
        #expect(viewModel.isYourTurn)
        // Robin has Dots and Boxes open, so its card comes first.
        #expect(viewModel.partnerGameKinds == [.dotsAndBoxes])
        let others = GameKind.allCases.filter { $0 != .dotsAndBoxes && viewModel.game($0) != nil }
        #expect(viewModel.hubGames.map(\.kind) == [.dotsAndBoxes] + others)
    }

    @Test func scenariosWithoutBoardGamesShowEachCardAsStartAGame() async {
        let scenario = DeveloperScenario.gamesHubYourTurn
        #expect(Fixture.boardGames(for: scenario).games.isEmpty)
        let drawAndGuess = DeveloperGamesScenarioFactory.state(for: scenario)
        #expect(Fixture.overview(for: scenario, drawAndGuess: drawAndGuess) == nil)

        let viewModel = DeveloperGamesScenarioFactory.gamesViewModel(for: scenario)
        viewModel.configure(participants: DeveloperGamesFixture.participants)
        await viewModel.reload()
        #expect(viewModel.connectFour.game.summary?.status == .notStarted)
    }
}

// MARK: - Dots and Boxes

extension BoardGameScenarioFixturesTests {
    @Test func dotsAndBoxesPhotoHasBoxesFromBothPartnersAndAHiddenPhoto() async throws {
        let setup = try firstSetup(.dotsAndBoxesPhoto)
        let game = setup.remoteGame()
        let board = try #require(DotsAndBoxesBoard.replay(setup.moves))
        #expect(game.photoMediaAssetID == Fixture.photoAssetID)
        #expect(game.turnUserID == me)
        #expect(board.boxCount(for: .one) == 3)
        #expect(board.boxCount(for: .two) == 3)
        #expect(!hasBoxToClose(board))

        let model = await openedModel(DotsAndBoxesBoard.self, kind: .dotsAndBoxes, scenario: .dotsAndBoxesPhoto)
        #expect(model.canPlay)
        #expect(model.snapshot?.photoMediaAssetID == Fixture.photoAssetID)
    }

    @Test func dotsAndBoxesExtraTurnHasOneBoxThatMyNextLineCloses() throws {
        let setup = try firstSetup(.dotsAndBoxesExtraTurn)
        #expect(setup.remoteGame().turnUserID == me)
        let board = try #require(DotsAndBoxesBoard.replay(setup.moves))
        let closing = try #require(board.applying(DeveloperBoardGamesMoves.dotsAndBoxesExtraTurnLine))
        #expect(closing.boxCount(for: .one) == board.boxCount(for: .one) + 1)
        // Closing a box keeps the turn.
        #expect(closing.next == .one)
        let closers = (0..<DotsAndBoxesBoard.moveLimit).filter { line in
            board.applying(line).map { $0.boxCount(for: .one) > board.boxCount(for: .one) } ?? false
        }
        #expect(closers == [DeveloperBoardGamesMoves.dotsAndBoxesExtraTurnLine])
    }

    @Test func dotsAndBoxesWonPhotoOpensOneLineBeforeTheLastBox() throws {
        let setup = try firstSetup(.dotsAndBoxesWonPhoto)
        let game = setup.remoteGame()
        #expect(game.status == .finished)
        #expect(game.winnerUserID == me)
        #expect(game.photoMediaAssetID == Fixture.photoAssetID)
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: 39))
        let before = try #require(DotsAndBoxesBoard.replay(Array(setup.moves.dropLast())))
        let after = try #require(DotsAndBoxesBoard.replay(setup.moves))
        // The last line closes the last box.
        #expect(before.boxes.count { $0 == nil } == 1)
        #expect(after.boxes.allSatisfy { $0 != nil })
        #expect(after.boxCount(for: .one) == 10)
        #expect(after.boxCount(for: .two) == 6)
    }

    @Test func dotsAndBoxesPlainIsTheSameGameWithoutAPhoto() throws {
        let plain = try firstSetup(.dotsAndBoxesPlain)
        let withPhoto = try firstSetup(.dotsAndBoxesPhoto)
        #expect(plain.moves == withPhoto.moves)
        #expect(plain.remoteGame().photoMediaAssetID == nil)
    }

    @Test func theGeneratedPhotoDecodesAndOnlyTheScenarioPhotoLoads() async throws {
        let provider = DeveloperBoardPhotoProvider()
        let data = try #require(await provider.imageData(for: Fixture.photoAssetID))
        let image = try #require(UIImage(data: data))
        #expect(image.size.width > 0)
        #expect(await provider.imageData(for: UUID()) == nil)
        #expect(await provider.imageData(for: nil) == nil)
    }

    private func hasBoxToClose(_ board: DotsAndBoxesBoard) -> Bool {
        (0..<DotsAndBoxesBoard.moveLimit).contains { line in
            board.applying(line).map { $0.next == board.next } ?? false
        }
    }
}

// MARK: - Ultimate Tic-Tac-Toe

extension BoardGameScenarioFixturesTests {
    @Test func ultimateTicTacToeForcedSendsMeToTheBottomLeftBoard() async throws {
        let setup = try firstSetup(.ultimateTicTacToeForced)
        #expect(setup.remoteGame().turnUserID == me)
        let board = try #require(UltimateTicTacToeBoard.replay(setup.moves))
        #expect(board.forced == DeveloperBoardGamesMoves.ultimateTicTacToeForcedBoard)
        #expect(board.openBoards == [6])

        let model = await openedModel(
            UltimateTicTacToeBoard.self,
            kind: .ultimateTicTacToe,
            scenario: .ultimateTicTacToeForced
        )
        #expect(model.canPlay)
        #expect(model.turnLabel == .yourTurn)
    }

    @Test func ultimateTicTacToeFreeLetsMePlayInAnyOpenBoard() throws {
        let setup = try firstSetup(.ultimateTicTacToeFree)
        #expect(setup.remoteGame().turnUserID == me)
        let board = try #require(UltimateTicTacToeBoard.replay(setup.moves))
        #expect(board.forced == nil)
        #expect(board.outcome == nil)
        // The board Robin pointed at is decided, and seven boards stay open.
        #expect(board.openBoards.count == 7)
    }

    @Test func ultimateTicTacToePartnerMoveOpensOneMoveBehindRobinsMove() async throws {
        let setup = try firstSetup(.ultimateTicTacToePartnerMove)
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: setup.moves.count - 1))
        let movers = try #require(UltimateTicTacToeBoard.movers(setup.moves))
        #expect(movers.last.map(setup.user) == partner)

        let model = await openedModel(
            UltimateTicTacToeBoard.self,
            kind: .ultimateTicTacToe,
            scenario: .ultimateTicTacToePartnerMove
        )
        // Robin's last move replays, then it is my turn.
        #expect(model.displayedMoves == setup.moves)
        #expect(model.lastMove?.isMine == false)
        #expect(model.canPlay)
    }

    @Test func ultimateTicTacToeWonEndsOnMyThreeBoardsInARow() throws {
        let setup = try firstSetup(.ultimateTicTacToeWon)
        let game = setup.remoteGame()
        #expect(game.status == .finished)
        #expect(game.winnerUserID == me)
        #expect(game.winLine == [2, 4, 6])
        #expect(setup.shown == BoardGameShownPosition(gameNumber: 9, moveCount: game.moves.count - 1))
    }
}
