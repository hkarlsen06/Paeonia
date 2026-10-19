import Foundation
import Testing
@testable import PaeoniaApp

/// The partner side of Mind Meld: the typing message and the invite.
@MainActor
struct MindMeldPartnerTests {
    private let fixtures = MindMeldFixtures()

    private func environment(_ round: RemoteMindMeldRound) -> MindMeldTestEnvironment {
        MindMeldTestEnvironment(state: fixtures.state(current: fixtures.game(rounds: [round])))
    }

    @Test func aMessageCarriesNoLettersAndIsTaggedWithTheGame() throws {
        let message = MindMeldLiveMessage(roundNumber: 3, isTyping: true)
        let data = try JSONEncoder().encode(GameLiveEnvelope(game: MindMeldLiveMessage.game, message: message))
        let text = try #require(String(bytes: data, encoding: .utf8))

        #expect(MindMeldLiveMessage.game == "mind_meld")
        #expect(text.contains("\"mind_meld\""))
        #expect(!text.contains("word"))
        #expect(GameLiveEnvelopeTag.isGameMessage(data, decoder: JSONDecoder()))
    }

    @Test func sendingAnInviteTellsTheServerAndShowsSent() async {
        let env = environment(fixtures.open(1))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(env.gamesGateway.inviteKinds == [.mindMeld])
        #expect(viewModel.invite == .sent(until: GameFixture.now.addingTimeInterval(GameInviteState.interval)))
        #expect(viewModel.notice == nil)

        // The button is gone for 15 minutes, so a second tap sends nothing.
        await viewModel.sendInvite()
        #expect(env.gamesGateway.inviteCount == 1)
    }
}
