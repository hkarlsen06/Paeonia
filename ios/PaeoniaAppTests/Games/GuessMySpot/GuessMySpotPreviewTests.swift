import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct GuessMySpotPreviewTests {
    @Test func finishedRoundPreviewExpiresAndLateMessagesCannotRestoreIt() async throws {
        let dependencies = DeveloperGamesScenarioFactory.dependencies(for: .guessMySpotGuess)
        let model = GuessMySpotViewModel(dependencies: dependencies, participants: DeveloperGamesFixture.participants)
        await model.reload()
        let roundID = try #require(model.round?.id)
        let jpeg = try #require(await GuessMySpotPhotoPreview.jpeg(
            from: DeveloperGuessMySpotScenarioFactory.photoData(.guessMySpotScenarioLake)
        ))
        model.receive(.photoPreview(roundID: roundID, jpeg: jpeg))
        #expect(model.roundPhotoPreview != nil)

        let result = try #require(DeveloperGuessMySpotScenarioFactory.revealed(for: .guessMySpotRevealClose))
        await dependencies.guessMySpotCache.saveState(result, ownerUserID: DeveloperGamesFixture.me)
        await model.reload()
        #expect(model.partnerPhotoPreview == nil)
        model.receive(.photoPreview(roundID: roundID, jpeg: jpeg))
        #expect(model.partnerPhotoPreview == nil)
    }

    @Test func nextPreviewSurvivesThePreviousRevealAndExpiresAfterItsOwnRound() async throws {
        let dependencies = DeveloperGamesScenarioFactory.dependencies(for: .guessMySpotRevealNextReady)
        let model = GuessMySpotViewModel(dependencies: dependencies, participants: DeveloperGamesFixture.participants)
        await model.reload()
        let connection = WidgetLiveConnection(coupleID: UUID(), ticketProvider: { _ in nil })
        let room = WidgetLiveDrawing(connection: connection, role: .result)
        model.attach(room)
        defer { room.stop() }
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "choosing"))
        let next = try #require(DeveloperGuessMySpotScenarioFactory.nextReadyState())
        let nextID = try #require(next.currentRound?.id)
        let jpeg = try #require(await GuessMySpotPhotoPreview.jpeg(
            from: DeveloperGuessMySpotScenarioFactory.photoData(.guessMySpotScenarioLake)
        ))
        model.receive(.photoPreview(roundID: nextID, jpeg: jpeg))
        model.recompute()
        #expect(model.partnerPhotoPreview?.roundID == nextID)
        model.continueFromReveal()
        #expect(model.phase == .waitingForPhoto)
        #expect(model.partnerPhotoPreview?.roundID == nextID)

        await dependencies.guessMySpotCache.saveState(next, ownerUserID: DeveloperGamesFixture.me)
        await model.reload()
        #expect(model.phase == .guess)
        #expect(model.roundPhotoPreview != nil)

        var finished = next
        finished.currentRound?.guess = DeveloperGuessMySpotScenarioFactory.lake
        await dependencies.guessMySpotCache.saveState(finished, ownerUserID: DeveloperGamesFixture.me)
        await model.reload()
        #expect(model.partnerPhotoPreview == nil)
    }
}
