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
        #expect(viewModel.drawAndGuess.summary?.status == .yourTurnToDraw)
        #expect(viewModel.partnerIsHere(in: .drawAndGuess))
        #expect(viewModel.drawAndGuess.summary?.score == .against(mine: 8, partner: 5))
        #expect(viewModel.isYourTurn)
        // The Us tab shows the game the partner is in.
        #expect(viewModel.partnerGame?.kind == .drawAndGuess)
    }

    @Test func thePartnersTurnShowsNoTabBadge() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil)
        )
        let viewModel = viewModel(GamesTestEnvironment(state: state))

        await viewModel.load()

        #expect(viewModel.drawAndGuess.summary?.status == .waitingForPartner)
        #expect(!viewModel.isYourTurn)
        #expect(viewModel.partnerGame == nil)
    }

    @Test func theSettingsComeFromTheSharedOverviewNotFromAGame() async {
        // Draw & Guess has no state yet, and the overview already has the settings.
        let env = GamesTestEnvironment(state: nil)
        let overview = RemoteGamesOverview(
            userID: GameFixture.me,
            partnerUserID: GameFixture.partner,
            coupleID: DeveloperScenarioFixture.coupleID,
            settings: GameFixture.settings(),
            presence: []
        )
        await env.cache.saveOverview(overview, ownerUserID: GameFixture.me)
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.screen == .hub)
        #expect(viewModel.settings == GameFixture.settings())
        #expect(viewModel.drawAndGuess.summary == nil)
    }

    @Test func aLateOverviewReadNeverHidesNewerSettingsOrReturnsAfterAPurge() async {
        let cache = InMemoryGamesCache()
        func overview(_ settings: RemoteGameSettings?) -> RemoteGamesOverview {
            RemoteGamesOverview(
                userID: GameFixture.me,
                partnerUserID: GameFixture.partner,
                coupleID: DeveloperScenarioFixture.coupleID,
                settings: settings,
                presence: []
            )
        }
        let beforeSetup = overview(nil)
        let afterSetup = overview(GameFixture.settings())

        // A read starts, the live feed saves the finished setup, then the read answers from before it.
        let early = await cache.beginOverviewFetch()
        await cache.saveOverview(afterSetup, ownerUserID: GameFixture.me)
        #expect(await cache.saveFetchedOverview(beforeSetup, ownerUserID: GameFixture.me, ticket: early) == false)
        #expect(await cache.document(ownerUserID: GameFixture.me).overview == afterSetup)

        // A live update sent before the settings changed does not hide a read that has them.
        await cache.saveOverview(beforeSetup, ownerUserID: GameFixture.me)
        let late = await cache.beginOverviewFetch()
        await cache.saveOverview(beforeSetup, ownerUserID: GameFixture.me)
        #expect(await cache.saveFetchedOverview(afterSetup, ownerUserID: GameFixture.me, ticket: late))

        // A read that started before a purge is not saved after it.
        let beforePurge = await cache.beginOverviewFetch()
        await cache.clearAll()
        #expect(await cache.saveFetchedOverview(afterSetup, ownerUserID: GameFixture.me, ticket: beforePurge) == false)
        #expect(await cache.document(ownerUserID: GameFixture.me).overview == nil)
    }

    @Test func theHubListsThePartnersGameFirstThenYourTurnThenCatalogOrder() {
        let built: [GameKind] = [.storyChain, .drawAndGuess, .mindMeld]
        func order(partner: [GameKind] = [], yourTurn: Set<GameKind> = []) -> [GameKind] {
            GamesViewModel.hubOrder(built, partnerGames: partner, yourTurn: yourTurn)
        }

        #expect(order() == [.drawAndGuess, .mindMeld, .storyChain])
        #expect(order(partner: [.storyChain]) == [.storyChain, .drawAndGuess, .mindMeld])
        // A game that is not built never shows, even when the partner is in it.
        #expect(order(partner: [.connectFour]) == [.drawAndGuess, .mindMeld, .storyChain])
        #expect(order(yourTurn: [.mindMeld]) == [.mindMeld, .drawAndGuess, .storyChain])
        // The partner's game stays on top, even above a game waiting for your turn.
        #expect(order(partner: [.storyChain], yourTurn: [.mindMeld]) == [.storyChain, .mindMeld, .drawAndGuess])
        #expect(
            order(partner: [.drawAndGuess], yourTurn: [.drawAndGuess, .storyChain])
                == [.drawAndGuess, .storyChain, .mindMeld]
        )
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
        env.gateway.fail("overview")
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
