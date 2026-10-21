import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// The reveal and the seen mark.
extension DrawAndGuessViewModelTests {
    // MARK: Reveal and result seen

    private var solvedByMe: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(
                state: .solved,
                drawer: GameFixture.partner,
                hasDrawing: true,
                solveMs: 18_400,
                speedBonus: 1,
                firstTryBonus: 1,
                personalBest: true
            ),
            choices: GameFixture.choices
        )
    }

    @Test func theRevealShowsTimePointsAndBothBonuses() async {
        let viewModel = environment(solvedByMe).viewModel()
        await viewModel.reload()

        let reveal = viewModel.reveal
        #expect(viewModel.phase == .reveal)
        #expect(reveal?.outcome == .iSolvedIt)
        #expect(reveal?.solveDuration == 18.4)
        #expect(reveal?.speedBonus == 1)
        #expect(reveal?.firstTryBonus == 1)
        #expect(reveal?.personalBest == true)
        #expect(reveal?.pointsForMe == 4)
        #expect(reveal?.pointsForCouple == 2)
        #expect(reveal?.isConfirmed == true)
        #expect(viewModel.isNextTurnMine)
    }

    @Test func continuingFromTheRevealSavesTheSeenMarkOnThePhoneAtOnce() async throws {
        let env = environment(solvedByMe)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .reveal)

        await viewModel.continueFromReveal()

        // The mark waits in the queue for the network. Continue never waits for it.
        #expect(viewModel.phase == .chooseWord)
        let payload = try JSONDecoder().decode(
            GameResultSeenPayload.self,
            from: try #require(await env.queued(.markGameRoundResultSeen).first?.requestData)
        )
        #expect(payload.roundID == GameFixture.roundID)
        #expect(await env.queued(.markGameRoundResultSeen).count == 1)
    }
}
