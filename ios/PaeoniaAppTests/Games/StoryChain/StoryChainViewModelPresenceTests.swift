import Foundation
import Testing
@testable import PaeoniaApp

/// The heartbeat, the partner's presence, the room role, and the invite.
@MainActor
struct StoryChainViewModelPresenceTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    @Test func theHeartbeatNamesTheGameAndStopsWhenTheScreenLeaves() async {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let viewModel = environment.viewModel()

        await viewModel.start()
        let beat = await waitUntil { environment.gateway.presence == [true] }
        #expect(beat)
        #expect(environment.gateway.presenceKinds == [.storyChain])

        viewModel.stop()
        let left = await waitUntil { environment.gateway.presence == [true, false] }
        #expect(left)
    }

    @Test func theOverviewHeartbeatSaysWhetherThePartnerIsHere() async {
        func presence(partnerPresent: Bool) -> RemoteGamePresence {
            RemoteGamePresence(kind: .storyChain, myPresent: false, partnerPresent: partnerPresent, lastInviteAt: nil)
        }
        let lines = [Env.line(1, by: Fixture.me)]
        let here = Env(
            state: Env.writing(turn: Fixture.partner, lines: lines),
            presence: [presence(partnerPresent: true)]
        ).viewModel()
        await here.reload()
        #expect(here.partnerPresence == .here)
        #expect(here.invite == .hidden)

        let away = Env(
            state: Env.writing(turn: Fixture.partner, lines: lines),
            presence: [presence(partnerPresent: false)]
        ).viewModel()
        await away.reload()
        #expect(away.partnerPresence == .away)
        #expect(away.invite == .available)
    }

    @Test func thePartnersRoleInTheRoomDecidesWhatTheirScreenIs() async {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let viewModel = environment.viewModel()
        await viewModel.reload()
        environment.connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))

        let expected: [(String, StoryChainPartnerPresence)] = [
            ("present", .here),
            ("result", .result),
            ("choosing", .choosing),
            ("watching", .reading),
            ("drawing", .writing),
        ]
        for (role, presence) in expected {
            environment.connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role))
            viewModel.recompute()
            #expect(viewModel.partnerPresence == presence)
        }

        environment.connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        viewModel.recompute()
        #expect(viewModel.partnerPresence == .away)
    }

    @Test func myRoleInTheRoomFollowsThePhase() async {
        let writing = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let writingModel = writing.viewModel()
        await writingModel.reload()
        #expect(writing.room.role == .drawing)

        let waiting = Env(state: Env.writing(turn: Fixture.partner, lines: [Env.line(1, by: Fixture.me)]))
        let waitingModel = waiting.viewModel()
        await waitingModel.reload()
        #expect(waiting.room.role == .watching)

        let picking = Env.choosing(openings: Env.openings)
        let pickingModel = picking.viewModel()
        await pickingModel.reload()
        #expect(picking.room.role == .choosing)
    }

    @Test func anInviteIsSentOnceAndThenWaits() async {
        let environment = Env(state: Env.writing(turn: Fixture.partner, lines: [Env.line(1, by: Fixture.me)]))
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(viewModel.invite == .available)

        await viewModel.sendInvite()
        await viewModel.sendInvite()

        #expect(environment.gateway.inviteKinds == [.storyChain])
        #expect(viewModel.invite == .sent(until: GameFixture.now.addingTimeInterval(GameInviteState.interval)))
    }
}
