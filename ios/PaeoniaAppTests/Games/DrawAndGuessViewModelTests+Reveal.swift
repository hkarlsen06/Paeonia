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
                firstTryBonus: 1
            ),
            choices: GameFixture.choices
        )
    }

    @Test func theRevealShowsPointsAndBothBonuses() async {
        let viewModel = environment(solvedByMe).viewModel()
        await viewModel.reload()

        let reveal = viewModel.reveal
        #expect(viewModel.phase == .reveal)
        #expect(reveal?.outcome == .iSolvedIt)
        #expect(reveal?.speedBonus == 1)
        #expect(reveal?.firstTryBonus == 1)
        #expect(reveal?.pointsForMe == 4)
        #expect(reveal?.isConfirmed == true)
        #expect(viewModel.isNextTurnMine)
    }
}
