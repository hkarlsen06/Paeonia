import Foundation
import Testing
@testable import PaeoniaApp

/// Choosing an opening, starting a story, and creating the couple's game.
@MainActor
struct StoryChainViewModelOpeningTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    @Test func myTurnToChooseShowsTheThreeOpenings() async {
        let viewModel = Env.choosing(openings: Env.openings).viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .chooseOpening)
        #expect(viewModel.openingChoices == Env.openings)
        #expect(!viewModel.openingsUnavailable)
    }

    @Test func noOpeningsOnMyTurnIsTheOfflineCase() async {
        let viewModel = Env.choosing(openings: nil).viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .chooseOpening)
        #expect(viewModel.openingChoices.isEmpty)
        #expect(viewModel.openingsUnavailable)
    }

    @Test func aPickedOpeningThatLeavesTheOfferIsDropped() async {
        let viewModel = Env.choosing(openings: Env.openings).viewModel()
        await viewModel.reload()

        viewModel.selectedOpening = .own
        await viewModel.reload()
        #expect(viewModel.selectedOpening == .own)

        viewModel.selectedOpening = .opening(RemoteStoryOpening(openingID: "gone", text: "Not offered."))
        await viewModel.reload()
        #expect(viewModel.selectedOpening == nil)
    }

    @Test func startingAStoryQueuesTheStartAndMovesToWriting() async throws {
        let environment = Env.choosing(openings: Env.openings)
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.selectedOpening = .opening(Env.openings[1])

        await viewModel.startStory()

        let start = try #require(await environment.queuedStarts().first)
        #expect(start.gameID == Fixture.gameID)
        #expect(start.openingID == "en-bus")
        #expect(start.openingText == "The last bus left without a driver.")
        #expect(viewModel.phase == .writing)
        #expect(viewModel.page.opening == "The last bus left without a driver.")
        #expect(viewModel.selectedOpening == nil)
    }

    @Test func startingWithMyOwnLineQueuesNoOpening() async throws {
        let environment = Env.choosing(openings: Env.openings)
        let viewModel = environment.viewModel()
        await viewModel.reload()
        viewModel.selectedOpening = .own

        await viewModel.startStory()

        let start = try #require(await environment.queuedStarts().first)
        #expect(start.openingID == nil)
        #expect(start.openingText == nil)
        #expect(viewModel.phase == .writing)
        #expect(viewModel.page.opening == nil)
    }

    @Test func startingNeedsAPickedOpening() async {
        let environment = Env.choosing(openings: Env.openings)
        let viewModel = environment.viewModel()
        await viewModel.reload()

        await viewModel.startStory()

        #expect(await environment.queuedStarts().isEmpty)
        #expect(viewModel.phase == .chooseOpening)
    }

    // MARK: Creating the game

    @Test func aMissingGameIsCreatedOncePerAppearance() async {
        let environment = Env(state: Env.state(nil))
        let created = Env.state(
            Fixture.game(.choosingOpening, turn: Fixture.me, current: nil, stories: 0),
            openings: Env.openings
        )
        environment.storyGateway.setStateToLoad(created)
        let viewModel = environment.viewModel()

        await viewModel.start()
        let didCreate = await waitUntil { viewModel.phase == .chooseOpening }
        viewModel.recompute()

        #expect(didCreate)
        #expect(environment.storyGateway.calls.filter { $0 == "ensure" }.count == 1)
        viewModel.stop()
    }

    @Test func aFailedCreateSaysSoAndIsNotRepeated() async {
        let environment = Env(state: Env.state(nil))
        environment.storyGateway.setEnsureFails(true)
        let viewModel = environment.viewModel()

        await viewModel.start()
        let failed = await waitUntil { viewModel.startFailed }
        viewModel.recompute()

        #expect(failed)
        #expect(viewModel.notice == .couldNotStartGame)
        #expect(environment.storyGateway.calls.filter { $0 == "ensure" }.count == 1)
        viewModel.stop()
    }
}
