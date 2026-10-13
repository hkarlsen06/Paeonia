import Foundation
import Testing
@testable import PaeoniaApp

/// The Games tab: setup the first time, the partner's choices once, then the hub.
@MainActor
struct GamesViewModelTests {
    private func viewModel(
        _ env: GamesTestEnvironment
    ) -> GamesViewModel {
        let viewModel = GamesViewModel(dependencies: env.dependencies())
        viewModel.configure(participants: GameFixture.participants)
        return viewModel
    }

    @Test func aCoupleThatHasNotChosenSeesSetupWithTheirOwnLanguagePreselected() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil), hasSeenSettings: false)
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.screen == .setup)
        #expect(viewModel.draftLanguage == GameLanguage.preferred())
        #expect(viewModel.draftPlayStyle == .against)
    }

    @Test func finishingSetupSavesTheChoicesAndOpensTheHub() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil), hasSeenSettings: false)
        let afterSetup = GameFixture.state(
            settings: GameFixture.settings(),
            game: nil
        )
        env.gateway.setStateToLoad(afterSetup)
        let viewModel = viewModel(env)
        await viewModel.load()
        viewModel.draftPlayStyle = .together
        viewModel.draftLanguage = .nb

        await viewModel.finishSetup()

        #expect(env.gateway.calls.contains("setSettings"))
        #expect(viewModel.screen == .hub)
        let coupleID = DeveloperScenarioFixture.coupleID
        #expect(await env.cache.hasSeenSettings(coupleID: coupleID, ownerUserID: GameFixture.me))
    }

    @Test func thePartnerWhoArrivesLaterSeesWhatWasPickedOnceThenTheHub() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(by: GameFixture.partner),
            game: nil
        )
        let env = GamesTestEnvironment(state: state, hasSeenSettings: false)
        let viewModel = viewModel(env)

        await viewModel.load()
        guard case let .partnerPicked(settings) = viewModel.screen else {
            Issue.record("Expected the partner-picked moment, got \(viewModel.screen)")
            return
        }
        #expect(settings.updatedByUserID == GameFixture.partner)

        await viewModel.acknowledgePartnerPicked()
        #expect(viewModel.screen == .hub)

        // A new view model on the same cache never shows it again.
        let again = self.viewModel(env)
        await again.load()
        #expect(again.screen == .hub)
    }

    @Test func settingsThisPersonChoseNeverShowTheMoment() async {
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        let env = GamesTestEnvironment(state: state, hasSeenSettings: false)
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.screen == .hub)
    }

    @Test func theHubSummaryShowsWhoseTurnItIsAndTheScore() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            choices: GameFixture.choices,
            partnerIsHere: true
        )
        let viewModel = viewModel(GamesTestEnvironment(state: state))

        await viewModel.load()

        #expect(viewModel.screen == .hub)
        #expect(viewModel.hubSummary?.status == .yourTurnToDraw)
        #expect(viewModel.hubSummary?.partnerIsHere == true)
        #expect(viewModel.hubSummary?.score == .against(mine: 8, partner: 5))
    }

    @Test func changingTheSettingsLaterKeepsTheHubAndAFailureShowsANotice() async {
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        let env = GamesTestEnvironment(state: state)
        env.gateway.setStateToLoad(state)
        let viewModel = viewModel(env)
        await viewModel.load()

        let saved = await viewModel.saveSettings(playStyle: .together, language: .nb)
        #expect(saved)
        #expect(viewModel.screen == .hub)

        env.gateway.fail("setSettings")
        let failed = await viewModel.saveSettings(playStyle: .against, language: .en)
        #expect(!failed)
        #expect(viewModel.notice == .couldNotSaveSettings)
    }

    @Test func withNothingCachedAndNoConnectionTheTabSaysItNeedsOne() async {
        let env = GamesTestEnvironment(state: nil)
        env.gateway.fail("load")
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.screen == .unavailable)
    }

    @Test func theCacheKeepsEachPersonsContentApart() async {
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        let env = GamesTestEnvironment(state: state)

        let other = await env.cache.document(ownerUserID: UUID())

        #expect(other.state == nil)
        await env.cache.clearAll()
        #expect(await env.cache.document(ownerUserID: GameFixture.me).state == nil)
    }
}
