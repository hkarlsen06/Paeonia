import Foundation
import Testing
@testable import PaeoniaApp

/// Who is in the game, the heartbeat that says this screen is open, and the
/// invite, as they work in Draw & Guess. The viewer is `me`.
@MainActor
struct ExquisiteCorpseViewModelPresenceTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private typealias Env = ExquisiteCorpseTestEnvironment

    private var now: Date { Env.now }

    private func environment(
        partnerLastSeenAt: Date? = nil,
        lastInviteAt: Date? = nil
    ) -> Env {
        Env(state: Fixture.partnerBodyTurn(), partnerLastSeenAt: partnerLastSeenAt, lastInviteAt: lastInviteAt)
    }

    // MARK: What the partner is doing

    @Test func thePartnersRoleDecidesWhatTheScreenSays() async {
        let env = environment()
        let viewModel = env.viewModel()
        await viewModel.reload()
        env.connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))

        let expected: [(String, ExquisiteCorpsePartnerPresence)] = [
            ("present", .here),
            ("result", .result),
            ("watching", .watching),
            ("drawing", .drawing),
        ]
        for (role, presence) in expected {
            env.connection.partnerAnnounces(role: role)
            viewModel.recompute()
            #expect(viewModel.partnerPresence == presence)
        }

        env.connection.partnerLeaves()
        viewModel.recompute()
        #expect(viewModel.partnerPresence == .away)
    }

    @Test func aFreshHeartbeatMeansHereWhenTheRoomSaysNothing() async {
        let env = environment(partnerLastSeenAt: now.addingTimeInterval(-10))
        let viewModel = env.viewModel()

        await viewModel.reload()

        #expect(viewModel.partnerPresence == .here)
        #expect(viewModel.invite == .hidden)
    }

    @Test func aStaleHeartbeatMeansAway() async {
        let env = environment(partnerLastSeenAt: now.addingTimeInterval(-120))
        let viewModel = env.viewModel()

        await viewModel.reload()

        #expect(viewModel.partnerPresence == .away)
        #expect(viewModel.invite == .available)
    }

    @Test func thePartnerIsOnlyWatchingWhenTheirPhoneSaysSo() {
        let watching = ExquisiteCorpsePartnerPresence.watching
        #expect(watching.drawingLine(partnerName: "R") == .exquisiteCorpseDrawWatching("R"))
        #expect(ExquisiteCorpsePartnerPresence.here.drawingLine(partnerName: "R") == .exquisiteCorpseDrawHere("R"))
        #expect(ExquisiteCorpsePartnerPresence.drawing.drawingLine(partnerName: "R") == .exquisiteCorpseDrawHere("R"))
        #expect(ExquisiteCorpsePartnerPresence.result.drawingLine(partnerName: "R") == .exquisiteCorpseDrawHere("R"))
        #expect(ExquisiteCorpsePartnerPresence.away.drawingLine(partnerName: "R") == .exquisiteCorpseDrawLater("R"))
        #expect(ExquisiteCorpsePartnerPresence.result.isHere)
        #expect(!ExquisiteCorpsePartnerPresence.away.isHere)
        #expect(!ExquisiteCorpsePartnerPresence.here.isInRoom)
        #expect(ExquisiteCorpsePartnerPresence.watching.isInRoom)
    }

    // MARK: Invite

    @Test func theInviteGoesOutOnceAndThenReadsSent() async {
        let env = environment()
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.invite == .available)

        await viewModel.sendInvite()
        await viewModel.sendInvite()

        #expect(viewModel.invite == .sent(until: now.addingTimeInterval(15 * 60)))
        #expect(env.gamesGateway.inviteCount == 1)
        #expect(env.gamesGateway.inviteKinds == [.exquisiteCorpse])
    }

    @Test func anInviteTheServerAlreadyHasReadsSentAndIsNotSentAgain() async {
        let env = environment(lastInviteAt: now.addingTimeInterval(-60))
        let viewModel = env.viewModel()

        await viewModel.reload()
        await viewModel.sendInvite()

        #expect(viewModel.invite == .sent(until: now.addingTimeInterval(-60 + 15 * 60)))
        #expect(env.gamesGateway.inviteCount == 0)
    }

    @Test func aFailedInviteGoesBackToAvailableWithANotice() async {
        let env = environment()
        env.gamesGateway.setInviteError(URLError(.notConnectedToInternet))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(viewModel.invite == .available)
        #expect(viewModel.notice == .couldNotSendInvite)
    }

    @Test func theInviteStaysSentWhenTheServerSaysTooSoon() async {
        let env = environment()
        env.gamesGateway.setInviteError(
            PaeoniaConvexError.server(code: "53300", message: "you can send one invite every 15 minutes")
        )
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(viewModel.invite != .available)
        #expect(viewModel.notice == nil)
    }

    @Test func thePartnerBeingInTheRoomHidesTheInvite() async {
        let env = environment()
        let viewModel = env.viewModel()
        await viewModel.reload()
        env.connection.partnerJoins(role: "present")

        viewModel.recompute()
        await viewModel.sendInvite()

        #expect(viewModel.invite == .hidden)
        #expect(env.gamesGateway.inviteCount == 0)
    }

    // MARK: Heartbeat

    @Test func theScreenSaysItIsOpenForExquisiteCorpseAndClosedWhenItGoesAway() async {
        let env = environment()
        let viewModel = env.viewModel()

        await viewModel.start()
        let opened = await waitUntil { env.gamesGateway.presence.contains(true) }
        viewModel.stop()
        let closed = await waitUntil { env.gamesGateway.presence.contains(false) }

        #expect(opened)
        #expect(closed)
        #expect(Set(env.gamesGateway.presenceKinds) == [.exquisiteCorpse])
    }

    @Test func openingOurCreaturesKeepsTheGameGoingUntilBothScreensAreGone() async {
        let env = environment()
        let viewModel = env.viewModel()
        viewModel.screenAppeared()
        await viewModel.start()
        let opened = await waitUntil { env.gamesGateway.presence.contains(true) }
        #expect(opened)

        // "Our creatures" appears over the game, then the game screen goes away.
        viewModel.screenAppeared()
        viewModel.screenDisappeared()
        // Gives the deferred check time to run.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.isRunning)
        #expect(!env.gamesGateway.presence.contains(false))

        viewModel.screenDisappeared()
        let closed = await waitUntil { env.gamesGateway.presence.contains(false) }
        #expect(closed)
        #expect(!viewModel.isRunning)
    }

    @Test func goingToTheBackgroundSendsNotHereAndComingBackSendsHereAgain() async {
        let env = environment()
        let viewModel = env.viewModel()
        await viewModel.start()
        let opened = await waitUntil { env.gamesGateway.presence.contains(true) }
        #expect(opened)

        viewModel.scenePhaseChanged(isActive: false)
        let closed = await waitUntil { env.gamesGateway.presence.last == false }
        viewModel.scenePhaseChanged(isActive: true)
        let reopened = await waitUntil { env.gamesGateway.presence.last == true }
        viewModel.stop()

        #expect(closed)
        #expect(reopened)
    }

    @Test func aCoupleWithSettingsButNoGameTriesToCreateTheGameAndOffersAnotherTryWhenItFails() async {
        let env = Env(state: Fixture.state(game: nil))
        let viewModel = env.viewModel()

        await viewModel.reload()
        #expect(viewModel.phase == .preparing)
        // The scripted gateway refuses to create the game, whoever asks first.
        let failed = await waitUntil { viewModel.startFailed }

        #expect(failed)
        #expect(env.gateway.calls.contains("ensure"))
        #expect(viewModel.notice == .couldNotStartGame)
    }
}
