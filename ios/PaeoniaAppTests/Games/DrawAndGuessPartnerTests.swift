import Foundation
import Testing
@testable import PaeoniaApp

/// The partner side of Draw & Guess: the open-screen heartbeat, the invite, and
/// starting the couple's game.
@MainActor
struct DrawAndGuessPartnerTests {
    private func environment(_ state: RemoteDrawAndGuessState) -> GamesTestEnvironment {
        GamesTestEnvironment(state: state)
    }

    private var yourTurn: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            choices: GameFixture.choices
        )
    }

    // MARK: Presence and invite

    @Test func theInviteGoesOutOnceAndThenReadsSent() async {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.invite == .available)

        await viewModel.sendInvite()
        await viewModel.sendInvite()

        #expect(viewModel.invite == .sent(until: GameFixture.now.addingTimeInterval(15 * 60)))
        #expect(env.gateway.inviteCount == 1)
    }

    @Test func theInviteStaysSentWhenTheServerSaysTooSoon() async {
        let env = environment(yourTurn)
        env.gateway.setInviteError(
            PaeoniaConvexError.server(code: "53300", message: "you can send one invite every 15 minutes")
        )
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(viewModel.invite != .available)
        #expect(viewModel.notice == nil)
    }

    // MARK: Starting

    @Test func aCoupleWithSettingsButNoGameStartsTheGame() async {
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        let env = environment(state)
        env.gateway.setStateToLoad(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .preparing)

        await viewModel.startGameIfNeeded()

        #expect(env.gateway.calls.contains("ensure"))
        #expect(viewModel.phase == .chooseWord)
    }
}
