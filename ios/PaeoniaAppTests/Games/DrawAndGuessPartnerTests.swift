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

    @Test func theScreenSaysItIsOpenNowAndGoneWhenItCloses() async {
        let env = environment(yourTurn)
        let viewModel = env.viewModel(
            heartbeat: .seconds(30),
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )

        await viewModel.start()
        _ = await waitUntil { true }
        let opened = await {
            for _ in 0..<100 {
                if env.gateway.presence == [true] { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }()
        viewModel.stop()
        let closed = await {
            for _ in 0..<100 {
                if env.gateway.presence == [true, false] { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }()

        #expect(opened)
        #expect(closed)
    }

    @Test func theHeartbeatRepeatsWhileTheScreenIsOpen() async {
        let env = environment(yourTurn)
        let viewModel = env.viewModel(heartbeat: .seconds(30), sleep: { _ in await Task.yield() })

        await viewModel.start()
        let beats = await {
            for _ in 0..<200 {
                if env.gateway.presence.filter({ $0 }).count >= 3 { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }()
        viewModel.stop()

        #expect(beats)
    }

    @Test func goingToTheBackgroundSendsNotHere() async {
        let env = environment(yourTurn)
        let viewModel = env.viewModel()
        await viewModel.start()

        viewModel.scenePhaseChanged(isActive: false)
        let sent = await {
            for _ in 0..<100 {
                if env.gateway.presence.contains(false) { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }()
        viewModel.stop()

        #expect(sent)
    }

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

    @Test func aFailedInviteGoesBackToAvailableWithANotice() async {
        let env = environment(yourTurn)
        env.gateway.setInviteError(URLError(.notConnectedToInternet))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(viewModel.invite == .available)
        #expect(viewModel.notice == .couldNotSendInvite(.offline))
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

    @Test func thePartnerHereHidesTheInvite() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            choices: GameFixture.choices,
            partnerIsHere: true
        )
        let viewModel = environment(state).viewModel()
        await viewModel.reload()

        #expect(viewModel.partnerPresence == .here)
        #expect(viewModel.invite == .hidden)
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

    @Test func aFailedStartShowsANoticeAndAllowsARetry() async {
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        let env = environment(state)
        env.gateway.fail("ensure")
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.startGameIfNeeded()

        #expect(viewModel.startFailed)
        #expect(viewModel.notice == .couldNotStartGame(.other))
        #expect(viewModel.phase == .preparing)
    }

    @Test func noticesFromBackgroundSendsReachTheScreenOnce() async {
        let env = environment(yourTurn)
        await env.cache.recordNotice(.wordRejected, ownerUserID: GameFixture.me)
        let viewModel = env.viewModel()

        await viewModel.reload()
        #expect(viewModel.notice == .wordRejected)
        viewModel.clearNotice()
        await viewModel.reload()

        #expect(viewModel.notice == nil)
    }
}
