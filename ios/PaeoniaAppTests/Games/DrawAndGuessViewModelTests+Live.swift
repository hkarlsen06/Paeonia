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
}
