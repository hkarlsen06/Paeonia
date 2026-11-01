import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct GuessMySpotContinuationTests {
    @Test func nextPhotoUpdatesContinueWithoutLeavingTheResultAndCuesOnlyOnce() async throws {
        let dependencies = DeveloperGamesScenarioFactory.dependencies(for: .guessMySpotRevealNextReady)
        let viewModel = GuessMySpotViewModel(
            dependencies: dependencies,
            participants: DeveloperGamesFixture.participants
        )
        var turns = 0
        var steps = 0
        viewModel.attentionCue = GameAttentionCue(player: .init(turn: { turns += 1 }, step: { steps += 1 }))
        viewModel.isRunning = true
        viewModel.isActive = true
        await viewModel.reload()
        let resultID = try #require(viewModel.round?.id)
        #expect(viewModel.continuation == nil)
        #expect(turns == 0 && steps == 0)

        let next = try #require(DeveloperGuessMySpotScenarioFactory.nextReadyState())
        await dependencies.guessMySpotCache.saveState(next, ownerUserID: DeveloperGamesFixture.me)
        await viewModel.reload()
        #expect(viewModel.phase == .reveal(isHeld: false))
        #expect(viewModel.round?.id == resultID)
        #expect(viewModel.continuation?.status == .sentPhoto)
        #expect(turns == 1 && steps == 0)

        await viewModel.reload()
        viewModel.recompute()
        #expect(turns == 1 && steps == 0)

        viewModel.continueFromReveal()
        #expect(viewModel.phase == .guess)
        #expect(viewModel.round?.id == next.currentRound?.id)
        #expect(viewModel.continuation == nil)
        #expect(turns == 1 && steps == 0)
    }

    @Test func openingWithTheNextPhotoAlreadyReadyShowsTheLabelWithoutACue() async throws {
        let dependencies = DeveloperGamesScenarioFactory.dependencies(for: .guessMySpotRevealNextReady)
        let state = try #require(DeveloperGuessMySpotScenarioFactory.nextReadyState())
        await dependencies.guessMySpotCache.saveState(state, ownerUserID: DeveloperGamesFixture.me)
        let viewModel = GuessMySpotViewModel(
            dependencies: dependencies,
            participants: DeveloperGamesFixture.participants
        )
        var cues = 0
        viewModel.attentionCue = GameAttentionCue(player: .init(turn: { cues += 1 }, step: { cues += 1 }))
        viewModel.isRunning = true
        viewModel.isActive = true
        await viewModel.reload()

        #expect(viewModel.phase == .reveal(isHeld: false))
        #expect(viewModel.continuation?.status == .sentPhoto)
        #expect(cues == 0)
    }

    @Test func waitingRequiresThePartnerToLeaveThisResultAndDoesNotRepeatAfterReconnect() async throws {
        let dependencies = DeveloperGamesScenarioFactory.dependencies(for: .guessMySpotRevealSpotOn)
        let state = try #require(DeveloperGuessMySpotScenarioFactory.revealed(for: .guessMySpotRevealSpotOn))
        await dependencies.guessMySpotCache.saveState(state, ownerUserID: DeveloperGamesFixture.me)
        let viewModel = GuessMySpotViewModel(
            dependencies: dependencies,
            participants: DeveloperGamesFixture.participants
        )
        let connection = WidgetLiveConnection(coupleID: UUID(), ticketProvider: { _ in nil })
        let room = WidgetLiveDrawing(connection: connection, role: .result)
        viewModel.attach(room)
        var cues = 0
        viewModel.attentionCue = GameAttentionCue(player: .init(turn: { cues += 1 }, step: { cues += 1 }))
        viewModel.isRunning = true
        viewModel.isActive = true
        await viewModel.reload()

        func role(_ role: WidgetLivePresence.Role) {
            connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
            connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role.rawValue))
            viewModel.recompute()
        }
        // The sender was already waiting for this person's guess before the result.
        role(.present)
        #expect(viewModel.continuation == nil)
        role(.result)
        #expect(viewModel.continuation == nil)
        role(.present)
        #expect(viewModel.continuation?.status == .waiting)
        #expect(viewModel.phase == .reveal(isHeld: false))
        #expect(cues == 1)

        connection.onDisconnect?()
        viewModel.recompute()
        #expect(viewModel.continuation == nil)
        role(.present)
        #expect(viewModel.continuation?.status == .waiting)
        #expect(cues == 1)
        room.stop()
    }
}
