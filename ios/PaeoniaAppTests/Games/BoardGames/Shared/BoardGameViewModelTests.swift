import Foundation
import Testing
@testable import PaeoniaApp

/// The Connect Four screen's view model on in-memory parts: what the board shows
/// when it opens, how it replays the partner's moves, what a move of mine does,
/// and what the hub reads while the screen is closed. Endings, rematches and
/// the score are in `BoardGameViewModelEndingTests`.
@MainActor
struct BoardGameViewModelTests {
    private typealias Fixture = BoardGameDataFixture

    private let harness = BoardGameHarness()

    // MARK: Opening

    @Test func openingOnMyTurnAfterThePartnersMoveReplaysOnlyThatMove() async {
        // I dropped in column 3 and the partner answered in column 4. This phone never showed the game.
        let viewModel = await harness.openBoard(harness.game(moves: [3, 4]))
        defer { viewModel.stop() }

        // One wait means one replayed move, so the board started after my own move.
        #expect(harness.sleeps.waits.count == 1)
        #expect(viewModel.displayedMoves == [3, 4])
        #expect(viewModel.lastMove == BoardMoveEvent(number: 2, move: 4, player: .two, isMine: false))
        #expect(viewModel.canPlay)
        #expect(viewModel.turnLabel == .yourTurn)
        await harness.expectShown(game: 1, moves: 2)
    }

    @Test func openingAfterMyOwnMoveHasNothingToReplay() async {
        let viewModel = await harness.openBoard(harness.game(moves: [3, 4, 5]))
        defer { viewModel.stop() }

        #expect(harness.sleeps.waits.isEmpty)
        #expect(viewModel.displayedMoves == [3, 4, 5])
        #expect(viewModel.lastMove == nil)
        #expect(!viewModel.canPlay)
        #expect(viewModel.turnLabel == .partnerTurn)
    }

    @Test func openingAtTheShownPositionReplaysNothing() async {
        let viewModel = await harness.openBoard(harness.game(moves: [3, 4]), shown: harness.position(2))
        defer { viewModel.stop() }

        #expect(harness.sleeps.waits.isEmpty)
        #expect(viewModel.displayedMoves == [3, 4])
        #expect(viewModel.lastMove == nil)
        #expect(!viewModel.isReplaying)
        #expect(viewModel.canPlay)
    }

    @Test func openingBehindTheShownPositionReplaysEveryMoveSinceThen() async {
        // The phone showed my first move. The partner's two moves and my move between them are new.
        let viewModel = await harness.openBoard(harness.game(moves: [3, 4, 5, 2]), shown: harness.position(1))
        defer { viewModel.stop() }

        #expect(harness.sleeps.waits.count == 3)
        #expect(viewModel.displayedMoves == [3, 4, 5, 2])
        #expect(viewModel.lastMove == BoardMoveEvent(number: 4, move: 2, player: .two, isMine: false))
        await harness.expectShown(game: 1, moves: 4)
    }

    @Test func theReplayWaitsUntilTheBoardCanShowIt() async {
        await harness.save(harness.game(moves: [3, 4]))
        let viewModel = harness.makeViewModel()
        defer { viewModel.stop() }
        // Ludo's 3D board is still loading when the screen opens.
        viewModel.isWaitingForBoard = true
        await viewModel.start(prefersReducedMotion: true)

        // The board shows where this phone left the game and holds the partner's move.
        #expect(viewModel.displayedMoves == [3])
        #expect(!viewModel.isReplaying)
        #expect(harness.sleeps.waits.isEmpty)
        #expect(!viewModel.canPlay)

        viewModel.isWaitingForBoard = false
        let caughtUp = await waitUntil { viewModel.displayedMoves == [3, 4] && !viewModel.isReplaying }
        #expect(caughtUp)
        #expect(viewModel.lastMove == BoardMoveEvent(number: 2, move: 4, player: .two, isMine: false))
        #expect(viewModel.canPlay)
    }

    @Test func aBoardThatFinishedThePartnersMoveHandsOverTheTurnAtOnce() async {
        await harness.save(harness.game(moves: [3, 4]))
        let viewModel = harness.makeViewModel(partnerTiming: .seconds(120))
        defer { viewModel.stop() }
        await viewModel.start(prefersReducedMotion: false)
        let animating = await waitUntil { viewModel.displayedMoves == [3, 4] && viewModel.isReplaying }
        #expect(animating)
        #expect(!viewModel.canPlay)

        // An older move's signal changes nothing.
        viewModel.finishMoveAnimation(number: 1)
        #expect(viewModel.isReplaying)

        // Ludo's board says the pawn stands still and the die has landed.
        viewModel.finishMoveAnimation(number: 2)
        let handedOver = await waitUntil { !viewModel.isReplaying && viewModel.canPlay }
        #expect(handedOver)
    }

    @Test func aPartnerMoveThatArrivesWhileTheBoardIsOpenPlaysAsAMove() async {
        let viewModel = await harness.openBoard(harness.game(moves: [3]))
        defer { viewModel.stop() }
        #expect(!viewModel.canPlay)

        await harness.save(harness.game(moves: [3, 4]))
        await viewModel.reload()

        let caughtUp = await waitUntil { viewModel.displayedMoves == [3, 4] && !viewModel.isReplaying }
        #expect(caughtUp)
        #expect(viewModel.lastMove == BoardMoveEvent(number: 2, move: 4, player: .two, isMine: false))
        #expect(viewModel.canPlay)
        await harness.expectShown(game: 1, moves: 2)
    }

    // MARK: Playing

    @Test func playingAColumnShowsTheDiscAtOnceAndQueuesTheMoveWithTheStake() async {
        let game = harness.game()
        let viewModel = await harness.openBoard(game)
        defer { viewModel.stop() }
        #expect(viewModel.canPlay)
        #expect(viewModel.stakeState == .writable)
        viewModel.stakeDraft = "Loser makes coffee"

        await viewModel.play(3)

        #expect(viewModel.displayedMoves == [3])
        #expect(viewModel.board.discCount == 1)
        #expect(viewModel.lastMove == BoardMoveEvent(number: 1, move: 3, player: .one, isMine: true))
        #expect(!viewModel.canPlay)
        #expect(viewModel.turnLabel == .partnerTurn)
        #expect(viewModel.stakeState == .fixed("Loser makes coffee"))
        #expect(!viewModel.isWaitingToSend)
        let queued = await harness.queuedMoves()
        #expect(queued == [Fixture.move(3, on: game, expectedVersion: 1, stake: "Loser makes coffee")])
        await harness.expectShown(game: 1, moves: 1)
    }

    @Test(arguments: ["", "  \n "])
    func aBlankStakeIsNotSentWithTheFirstMove(draft: String) async {
        let game = harness.game()
        let viewModel = await harness.openBoard(game)
        defer { viewModel.stop() }
        viewModel.stakeDraft = draft

        await viewModel.play(3)

        #expect(await harness.queuedMoves() == [Fixture.move(3, on: game, expectedVersion: 1, stake: nil)])
        #expect(viewModel.stakeState == .hidden)
    }

    @Test func onlyTheFirstMoveOfTheGameCarriesTheStake() async {
        // My second move names the version after the first two moves.
        let game = harness.game(moves: [3, 4])
        let viewModel = await harness.openBoard(game, shown: harness.position(2))
        defer { viewModel.stop() }
        viewModel.stakeDraft = "Left over from before"

        await viewModel.play(2)

        #expect(await harness.queuedMoves() == [Fixture.move(2, on: game, expectedVersion: 3, stake: nil)])
        #expect(viewModel.displayedMoves == [3, 4, 2])
    }

    @Test func aMoveOutOfTurnQueuesNothing() async {
        let viewModel = await harness.openBoard(harness.game(moves: [3]))
        defer { viewModel.stop() }

        await viewModel.play(2)

        #expect(await harness.queuedMoves().isEmpty)
        #expect(viewModel.displayedMoves == [3])
    }

    @Test func aMoveInAFullColumnQueuesNothing() async {
        // Six discs in column 0 fill it, and it is my turn again.
        let viewModel = await harness.openBoard(harness.game(moves: [0, 0, 0, 0, 0, 0]), shown: harness.position(6))
        defer { viewModel.stop() }
        #expect(viewModel.canPlay)

        await viewModel.play(0)

        #expect(await harness.queuedMoves().isEmpty)
        #expect(viewModel.displayedMoves.count == 6)
        #expect(viewModel.lastMove == nil)
    }

    @Test(arguments: [[3], [3, 4]])
    func aMoveTheServerAlreadyTookIsNotAppliedTwice(serverMoves: [Int]) async {
        let viewModel = await harness.openBoard(harness.game())
        defer { viewModel.stop() }
        await viewModel.play(3)
        #expect(await harness.queuedMoves().count == 1)

        // The server took the move, and maybe the partner answered. The queue has not let go of the
        // move yet, and it names a version the game has left.
        await harness.save(harness.game(moves: serverMoves))
        await viewModel.reload()

        let caughtUp = await waitUntil { viewModel.displayedMoves == serverMoves && !viewModel.isReplaying }
        #expect(caughtUp)
        #expect(viewModel.board.discCount == serverMoves.count)
        #expect(viewModel.snapshot?.moves == serverMoves)
        #expect(viewModel.snapshot?.version == serverMoves.count + 1)
        #expect(viewModel.snapshot?.unsentCount == 0)
        #expect(!viewModel.isWaitingToSend)
        #expect(await harness.queuedMoves().count == 1)
    }

    @Test func aRefusedMoveFallsBackToTheServersGameWithoutIt() async throws {
        let viewModel = await harness.openBoard(harness.game(moves: [3, 4]), shown: harness.position(2))
        defer { viewModel.stop() }
        await viewModel.play(2)
        #expect(viewModel.displayedMoves == [3, 4, 2])

        // The server refused the move for good. The queue drops it and the live game never had it.
        try await harness.refuseQueuedMoves()
        await harness.cache.recordNotice(.moveRejected(.connectFour), ownerUserID: harness.me)
        await viewModel.reload()

        #expect(viewModel.displayedMoves == [3, 4])
        #expect(viewModel.board.discCount == 2)
        #expect(viewModel.snapshot?.moves == [3, 4])
        #expect(viewModel.lastMove == nil)
        #expect(viewModel.notice == .moveRejected)
        #expect(viewModel.canPlay)
        #expect(viewModel.turnLabel == .yourTurn)
        await harness.expectShown(game: 1, moves: 2)
    }

    // MARK: While the screen is closed

    @Test func theHubSummaryFollowsTheGameButTheBoardStaysUntouchedUntilTheScreenOpens() async {
        let viewModel = harness.makeViewModel()
        await harness.save(harness.game(moves: [3]))
        await viewModel.reload()
        #expect(viewModel.summary?.status == .partnerTurn)

        await harness.save(harness.game(moves: [3, 4]))
        await viewModel.reload()
        #expect(viewModel.summary?.status == .yourTurn)

        await harness.save(harness.game(moves: Fixture.connectFourWin, myWins: 1, gamesFinished: 1))
        await viewModel.reload()
        #expect(viewModel.summary?.status == .youWon)
        #expect(viewModel.summary?.score == .against(mine: 1, partner: 0))

        #expect(viewModel.displayedMoves.isEmpty)
        #expect(viewModel.displayedGameNumber == 0)
        #expect(viewModel.board == .initial)
        #expect(viewModel.lastMove == nil)
        #expect(!viewModel.showsOutcome)
        #expect(viewModel.result == nil)
        #expect(harness.sleeps.waits.isEmpty)
        await harness.expectNothingShown()
    }

    @Test func theHubSummaryNamesThePartnerWhenTheyWon() async {
        let viewModel = harness.makeViewModel()
        let game = harness.game(first: .partner, moves: Fixture.connectFourWin, partnerWins: 1, gamesFinished: 1)
        await harness.save(game)

        await viewModel.reload()

        #expect(viewModel.summary?.status == .partnerWon)
        #expect(viewModel.summary?.score == .against(mine: 0, partner: 1))
        await harness.expectNothingShown()
    }

    @Test func aCoupleWithoutAGameHasANotStartedSummary() async {
        let viewModel = harness.makeViewModel()
        await harness.cache.saveState(harness.state(), ownerUserID: harness.me)

        await viewModel.reload()

        #expect(viewModel.summary == BoardGameHubSummary(status: .notStarted, score: nil))
    }
}
