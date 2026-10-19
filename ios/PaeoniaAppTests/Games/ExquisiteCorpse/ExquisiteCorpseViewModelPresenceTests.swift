import Foundation
import Testing
@testable import PaeoniaApp

/// The invite to the partner. The viewer is `me`.
@MainActor
struct ExquisiteCorpseViewModelPresenceTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private typealias Env = ExquisiteCorpseTestEnvironment

    private var now: Date { Env.now }

    private func environment(
        partnerPresent: Bool = false,
        lastInviteAt: Date? = nil
    ) -> Env {
        Env(state: Fixture.partnerBodyTurn(), partnerPresent: partnerPresent, lastInviteAt: lastInviteAt)
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
}
