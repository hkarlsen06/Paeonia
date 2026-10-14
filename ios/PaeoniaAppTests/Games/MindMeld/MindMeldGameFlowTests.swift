import Foundation
import Testing
@testable import PaeoniaApp

/// Starting, finishing and restarting games through `MindMeldViewModel`.
@MainActor
struct MindMeldGameFlowTests {
    private let fixtures = MindMeldFixtures()

    private func environment(
        _ game: RemoteMindMeldGame?,
        previous: RemoteMindMeldGame? = nil
    ) -> MindMeldTestEnvironment {
        fixtures.environment(game, previous: previous)
    }

    // MARK: Starting a game

    @Test func theFirstGameStartsByItself() async {
        let started = fixtures.game(rounds: [fixtures.open(1)])
        let env = MindMeldTestEnvironment(state: nil)
        env.gateway.setStateToLoad(fixtures.state(current: nil))
        env.gateway.setStateAfterStart(fixtures.state(current: started))
        let viewModel = env.viewModel()

        await viewModel.start()
        let reachedWrite = await waitUntil { viewModel.phase == .write }
        viewModel.stop()

        #expect(reachedWrite)
        #expect(env.gateway.starts == 1)
        #expect(!viewModel.startFailed)
        #expect(!viewModel.isStartingGame)
    }

    @Test func aFailedFirstStartIsOfferedAgain() async {
        let started = fixtures.game(rounds: [fixtures.open(1)])
        let env = MindMeldTestEnvironment(state: nil)
        env.gateway.setStateToLoad(fixtures.state(current: nil))
        env.gateway.setStateAfterStart(fixtures.state(current: started))
        env.gateway.fail("start")
        let viewModel = env.viewModel()

        await viewModel.start()
        let failed = await waitUntil { viewModel.startFailed }
        #expect(failed)
        #expect(viewModel.phase == .starting)
        #expect(!viewModel.isStartingGame)
        // It does not keep trying by itself.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(env.gateway.starts == 0)
        #expect(env.gateway.calls.filter { $0 == "start" }.count == 1)

        env.gateway.unfail("start")
        await viewModel.retryStart()
        viewModel.stop()

        #expect(!viewModel.startFailed)
        #expect(viewModel.phase == .write)
        #expect(env.gateway.starts == 1)
    }

    @Test func aFailedFirstReadWithNothingCachedIsOfferedAgain() async {
        let env = MindMeldTestEnvironment(state: nil)
        env.gateway.fail("load")
        let viewModel = env.viewModel()

        await viewModel.start()
        viewModel.stop()

        #expect(viewModel.startFailed)
        #expect(viewModel.phase == .loading)
        #expect(env.gateway.starts == 0)

        env.gateway.unfail("load")
        env.gateway.setStateToLoad(fixtures.state(current: fixtures.game(rounds: [fixtures.open(1)])))
        await viewModel.retryStart()

        #expect(!viewModel.startFailed)
        #expect(viewModel.phase == .write)
    }

    @Test func playAgainMarksTheEndAndStartsANewGame() async throws {
        let finished = fixtures.meldedGame(seen: false)
        let started = fixtures.game(number: 2, rounds: [fixtures.open(1)])
        let env = environment(finished)
        env.gateway.setStateAfterStart(fixtures.state(current: started, previous: finished))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.playAgain()

        let ends = await env.queued(.markMindMeldEndSeen)
        let reveals = await env.queued(.markMindMeldRevealSeen)
        #expect(env.gateway.starts == 1)
        #expect(ends.count == 1)
        #expect(reveals.count == 1)
        // The old game's ending is marked seen, so the new game is next.
        #expect(viewModel.phase == .write)
        #expect(viewModel.game?.id == started.id)
        #expect(!viewModel.isStartingGame)
    }

    @Test func playAgainThatFailsShowsANoticeAndKeepsTheFinishedGame() async {
        let finished = fixtures.meldedGame(seen: true)
        let env = environment(finished)
        env.gateway.fail("start")
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .over)

        await viewModel.playAgain()

        #expect(viewModel.notice == .couldNotStartGame)
        #expect(viewModel.phase == .over)
        #expect(!viewModel.isStartingGame)
    }

    @Test func startingOverEndsTheGameInPlay() async {
        let playing = fixtures.game(rounds: [fixtures.open(1)])
        let started = fixtures.game(number: 2, rounds: [fixtures.open(1)])
        let env = environment(playing)
        env.gateway.setStateAfterStart(fixtures.state(current: started))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.restart()

        #expect(env.gateway.restarts == [playing.id])
        #expect(viewModel.game?.id == started.id)
        #expect(viewModel.phase == .write)
    }

    @Test func startingOverWorksFromTheRevealOfAGameInPlay() async {
        let playing = fixtures.game(rounds: [fixtures.revealed(1, seen: false), fixtures.open(2)])
        let started = fixtures.game(number: 2, rounds: [fixtures.open(1)])
        let env = environment(playing)
        env.gateway.setStateAfterStart(fixtures.state(current: started))
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)

        await viewModel.restart()

        #expect(env.gateway.restarts == [playing.id])
        #expect(viewModel.game?.id == started.id)
    }

    @Test func playAgainWaitsForACountStillOnThePhone() async {
        let near = fixtures.revealed(2, "dog", "dogs", outcome: .near, seen: false)
        let env = environment(fixtures.game(rounds: [fixtures.revealed(1), near, fixtures.open(3)]))
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.countIt()
        await viewModel.moveTask?.value
        #expect(viewModel.game?.state == .melded)

        // Offline: the count can't reach the server, so the server would still
        // hand back this game. Nothing starts, and the person hears why.
        await viewModel.playAgain()

        #expect(env.gateway.starts == 0)
        #expect(viewModel.notice == .couldNotStartGame)
        #expect(!viewModel.isStartingGame)
    }

    @Test func startingOverThatFailsShowsANotice() async {
        let env = environment(fixtures.game(rounds: [fixtures.open(1)]))
        env.gateway.fail("restart")
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.restart()

        #expect(viewModel.notice == .couldNotStartGame)
        #expect(viewModel.phase == .write)
    }

    @Test func startingOverIsOnlyForAGameInPlay() async {
        let finished = fixtures.meldedGame(seen: true)
        let env = environment(finished)
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.restart()

        #expect(env.gateway.restarts.isEmpty)
    }

    // MARK: The partner started over

    @Test func aPartnerRestartShowsTheNoteAndMarksTheEndSeenOnce() async throws {
        let old = fixtures.game(
            .ended,
            rounds: [fixtures.open(1)],
            reason: .restart,
            endedBy: fixtures.partner
        )
        let new = fixtures.game(number: 2, rounds: [fixtures.open(1)])
        let env = environment(new, previous: old)
        let viewModel = env.viewModel()

        await viewModel.reload()
        await viewModel.moveTask?.value
        #expect(viewModel.phase == .write)
        #expect(viewModel.showsPartnerRestartedNote)

        // More reads do not queue it again, and the note stays.
        await viewModel.reload()
        await viewModel.reload()
        await viewModel.moveTask?.value
        let marks = await env.queued(.markMindMeldEndSeen)
        #expect(marks.count == 1)
        #expect(try decodePayload(MindMeldEndSeenPayload.self, marks.first).gameID == old.id)
        #expect(viewModel.showsPartnerRestartedNote)

        // Locking in clears it.
        viewModel.draft = "ocean"
        viewModel.lockIn()
        #expect(!viewModel.showsPartnerRestartedNote)
    }

    @Test func myOwnRestartShowsNoNote() async {
        let old = fixtures.game(.ended, rounds: [fixtures.open(1)], reason: .restart, endedBy: fixtures.me)
        let new = fixtures.game(number: 2, rounds: [fixtures.open(1)])
        let viewModel = environment(new, previous: old).viewModel()

        await viewModel.reload()

        #expect(viewModel.phase == .write)
        #expect(!viewModel.showsPartnerRestartedNote)
    }
}
