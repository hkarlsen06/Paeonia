import Foundation
import Testing
@testable import PaeoniaApp

/// The board when the screen goes away or the app goes to the background:
/// nothing counts as shown unseen, and the same model carries on when the
/// screen comes back, as the hub keeps one model per game.
@MainActor
struct BoardGameViewModelLifecycleTests {
    private typealias Fixture = BoardGameDataFixture

    private let harness = BoardGameHarness()

    @Test func backgroundingDuringStartupDoesNotRestartPresence() async {
        await harness.save(harness.game(moves: [3, 4]))
        let viewModel = harness.makeViewModel()
        let startup = Task { await viewModel.start(prefersReducedMotion: true) }
        while !viewModel.isRunning { await Task.yield() }
        viewModel.scenePhaseChanged(isActive: false)
        await startup.value
        for _ in 0..<20 { await Task.yield() }
        #expect(!harness.env.gateway.presence.contains(true))
        viewModel.stop()
    }

    @Test func leavingDuringAMissedEndingShowsItAgainOnTheSameModel() async {
        let finished = harness.game(first: .partner, moves: Fixture.connectFourWin, partnerWins: 1, gamesFinished: 1)
        let viewModel = await harness.openBoard(harness.game(after: finished), shown: harness.position(6))
        #expect(viewModel.isShowingMissedEnding)

        viewModel.stop()
        await viewModel.start(prefersReducedMotion: true)
        defer { viewModel.stop() }

        // The ending was shown to its end before leaving, so the board goes on to the new game.
        let caughtUp = await waitUntil { !viewModel.isReplaying }
        #expect(caughtUp)
        #expect(!viewModel.isShowingMissedEnding)
        #expect(viewModel.displayedGameNumber == 2)
        #expect(viewModel.canPlay)
    }

    @Test func theBackgroundPausesTheBoardAndAMoveThatArrivesThenReplaysOnReturn() async {
        // My move was the last one, so it is the partner's turn.
        let viewModel = await harness.openBoard(harness.game(moves: [3, 4, 2]), shown: harness.position(3))
        defer { viewModel.stop() }

        viewModel.scenePhaseChanged(isActive: false)
        // The partner answers while the app is in the background.
        await harness.save(harness.game(moves: [3, 4, 2, 5]))
        await viewModel.reload()
        #expect(viewModel.displayedMoves == [3, 4, 2])
        await harness.expectShown(game: 1, moves: 3)

        viewModel.scenePhaseChanged(isActive: true)
        let caughtUp = await waitUntil { viewModel.displayedMoves == [3, 4, 2, 5] && !viewModel.isReplaying }
        #expect(caughtUp)
        #expect(viewModel.lastMove == BoardMoveEvent(number: 4, move: 5, player: .two, isMine: false))
        #expect(viewModel.canPlay)
    }

    @Test func aRematchDuringTheLastMovesAnimationKeepsTheEndingOnScreen() async {
        // The partner's winning move is one past what this phone showed.
        let finished = harness.game(first: .partner, moves: Fixture.connectFourWin, partnerWins: 1, gamesFinished: 1)
        await harness.save(finished)
        await harness.cache.markShown(harness.position(6), kind: .connectFour, ownerUserID: harness.me)
        let viewModel = harness.makeViewModel(partnerTiming: .seconds(120))
        await viewModel.start(prefersReducedMotion: false)
        defer { viewModel.stop() }
        let animating = await waitUntil { viewModel.displayedMoves == Fixture.connectFourWin && viewModel.isReplaying }
        #expect(animating)

        // The partner starts the next game while the winning disc still falls.
        await harness.save(harness.game(after: finished))
        await viewModel.reload()

        #expect(viewModel.isShowingMissedEnding)
        #expect(viewModel.displayedGameNumber == 1)
        #expect(viewModel.displayedMoves == Fixture.connectFourWin)
    }

    @Test func aNoticeWaitsUntilItsBoardIsOpen() async {
        await harness.save(harness.game(moves: [3, 4]))
        await harness.cache.recordNotice(.moveRejected(.connectFour), ownerUserID: harness.me)
        let viewModel = harness.makeViewModel()

        // The hub reads the model while the screen is closed.
        await viewModel.reload()
        #expect(viewModel.notice == nil)

        await viewModel.start(prefersReducedMotion: true)
        defer { viewModel.stop() }
        #expect(viewModel.notice == .moveRejected)
    }
}
