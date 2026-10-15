import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The live canvas and the replay of a sent drawing.
extension DrawAndGuessViewModelTests {
    // MARK: Live

    @Test func aLiveSolveWhileDrawingRevealsAndSendsTheDrawingAsItIs() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        let env = environment(drawingState)
        let viewModel = env.viewModel()
        await viewModel.reload()
        viewModel.board.canvasDidLayout(side: 320)
        viewModel.board.replace(with: GameFixture.umbrella())
        #expect(viewModel.phase == .drawing)

        // The partner solves it live: the server's state moves on.
        await env.cache.saveState(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
                round: GameFixture.round(
                    state: .solved,
                    drawer: GameFixture.me,
                    attempts: [("cat", false), ("umbrella", true)],
                    solveMs: 9_000,
                    speedBonus: 1
                )
            ),
            ownerUserID: GameFixture.me
        )
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.reveal?.outcome == .partnerSolvedIt)
        #expect(viewModel.reveal?.pointsForMe == 2)
        #expect(viewModel.reveal?.attempts.map(\.text) == ["cat", "umbrella"])
        let sent = await waitUntil { viewModel.round?.isDrawingSent == true }
        #expect(sent)
        #expect(await env.queued(.submitGameDrawing).count == 1)
        #expect(viewModel.finalDrawing != nil)
    }

    @Test func theGuesserWatchingLiveKeepsTheLiveCanvasWhenTheDrawerPressesDone() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let env = environment(drawingState)
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = env.viewModel(live: room)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.reload()
        #expect(viewModel.phase == .waitingForDrawing)

        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        sendPartnerCanvasSnapshot(on: connection)
        viewModel.recompute()
        #expect(viewModel.phase == .watchingLive)
        #expect(viewModel.partnerPresence == .drawing)

        await env.cache.saveState(guessing, ownerUserID: GameFixture.me)
        await viewModel.reload()

        #expect(viewModel.phase == .guessing)
        #expect(viewModel.guessSource == .live)
    }

    // MARK: Replay

    @Test func theReplayStartsOnceTheDrawingIsLoadedAndTheGuesserIsMarkedAsHavingSeenIt() async {
        let env = environment(guessing)
        let viewModel = env.viewModel()
        await viewModel.reload()

        let ready = await waitUntil { viewModel.isReplayReady }

        #expect(ready)
        #expect(viewModel.guessSource == .replay)
        #expect(env.transfer.downloads == [GameFixture.assetID])
        let marked = await waitUntil { true }
        #expect(marked)
        let seen = await {
            for _ in 0..<100 {
                if env.gateway.seenRounds == [GameFixture.roundID] { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }()
        #expect(seen)
        // Past the end, the whole drawing shows.
        #expect(viewModel.replayDrawing(atWall: .greatestFiniteMagnitude, side: 320).strokes.count == 3)
        // At the very start only the first point of the first stroke shows.
        #expect(viewModel.replayDrawing(atWall: -1, side: 320).strokes.count < 3)
    }
}
