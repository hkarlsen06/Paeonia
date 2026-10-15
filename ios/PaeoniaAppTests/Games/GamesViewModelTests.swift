import Foundation
import Testing
@testable import PaeoniaApp

/// The Games tab: the hub at once, and the first-time steps before the first game.
@MainActor
struct GamesViewModelTests {
    private func viewModel(
        _ env: GamesTestEnvironment
    ) -> GamesViewModel {
        let viewModel = GamesViewModel(dependencies: env.dependencies())
        viewModel.configure(participants: GameFixture.participants)
        return viewModel
    }

    private let ludo = GamesDestination.game(.ludo)

    private func step(_ viewModel: GamesViewModel) -> String {
        switch viewModel.introStep {
        case .setup: "setup"
        case .partnerPicked: "partnerPicked"
        case .mark: "mark"
        case nil: "none"
        }
    }

    @Test func aCoupleThatHasNotChosenSeesTheHubAndSetupWhenAGameOpens() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil), hasSeenSettings: false)
        let viewModel = viewModel(env)

        await viewModel.load()
        #expect(viewModel.screen == .hub)
        #expect(viewModel.draftLanguage == GameLanguage.preferred())
        #expect(viewModel.draftPlayStyle == .against)

        // A history screen is not a game, so it opens at once.
        viewModel.open(.drawAndGuessHistory)
        #expect(viewModel.destinationToOpen == .drawAndGuessHistory)
        #expect(step(viewModel) == "none")
        viewModel.destinationToOpen = nil

        viewModel.open(ludo)
        #expect(step(viewModel) == "setup")
        #expect(viewModel.destinationToOpen == nil)
    }

    @Test func finishingSetupSavesTheChoicesThenAsksForAMarkThenOpensTheGame() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil), hasSeenSettings: false)
        let afterSetup = GameFixture.state(
            settings: GameFixture.settings(),
            game: nil
        )
        env.gateway.setStateToLoad(afterSetup)
        let viewModel = viewModel(env)
        await viewModel.load()
        viewModel.open(ludo)
        viewModel.draftPlayStyle = .together
        viewModel.draftLanguage = .nb

        await viewModel.finishSetup()

        #expect(env.gateway.calls.contains("setSettings"))
        #expect(viewModel.screen == .hub)
        let coupleID = DeveloperScenarioFixture.coupleID
        #expect(await env.cache.hasSeenSettings(coupleID: coupleID, ownerUserID: GameFixture.me))
        #expect(step(viewModel) == "mark")
        #expect(viewModel.destinationToOpen == nil)

        // Closing the mark sheet, saved or not, opens the game.
        viewModel.introDismissed()
        #expect(step(viewModel) == "none")
        #expect(viewModel.destinationToOpen == ludo)

        // The next game opens at once.
        viewModel.destinationToOpen = nil
        viewModel.open(.game(.connectFour))
        #expect(viewModel.destinationToOpen == .game(.connectFour))
    }

    @Test func closingSetupLeavesThePersonOnTheHub() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil), hasSeenSettings: false)
        let viewModel = viewModel(env)
        await viewModel.load()
        viewModel.open(ludo)

        viewModel.introDismissed()

        #expect(step(viewModel) == "none")
        #expect(viewModel.destinationToOpen == nil)
    }

    @Test func setupOpensTheGameAtOnceForSomeoneWhoAlreadyDrewAMark() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil), hasSeenSettings: false)
        env.gateway.setStateToLoad(GameFixture.state(settings: GameFixture.settings(), game: nil))
        var dependencies = env.dependencies()
        dependencies.boardGamesCache = InMemoryBoardGamesCache(
            marks: RemoteBoardGameMarks(
                userID: GameFixture.me,
                mine: RemoteBoardGameMark(drawing: "bmV3", updatedAt: GameFixture.now),
                partner: nil
            ),
            ownerUserID: GameFixture.me
        )
        let viewModel = GamesViewModel(dependencies: dependencies)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.load()
        viewModel.open(ludo)

        await viewModel.finishSetup()

        #expect(step(viewModel) == "none")
        #expect(viewModel.destinationToOpen == ludo)
    }

    @Test func thePartnerWhoArrivesLaterSeesWhatWasPickedOnceBeforeTheFirstGame() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(by: GameFixture.partner),
            game: nil
        )
        let env = GamesTestEnvironment(state: state, hasSeenSettings: false)
        let viewModel = viewModel(env)

        await viewModel.load()
        #expect(viewModel.screen == .hub)
        viewModel.open(ludo)
        guard case let .partnerPicked(settings) = viewModel.introStep else {
            Issue.record("Expected the partner-picked moment, got \(step(viewModel))")
            return
        }
        #expect(settings.updatedByUserID == GameFixture.partner)

        await viewModel.acknowledgePartnerPicked()
        #expect(step(viewModel) == "mark")

        // A new view model on the same cache opens games at once.
        let again = self.viewModel(env)
        await again.load()
        again.open(ludo)
        #expect(step(again) == "none")
        #expect(again.destinationToOpen == ludo)
    }

    @Test func changingWhatThePartnerPickedStillAsksForAMark() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(by: GameFixture.partner),
            game: nil
        )
        let env = GamesTestEnvironment(state: state, hasSeenSettings: false)
        env.gateway.setStateToLoad(GameFixture.state(settings: GameFixture.settings(), game: nil))
        let viewModel = viewModel(env)
        await viewModel.load()
        viewModel.open(ludo)

        viewModel.changePartnerPicked()
        #expect(step(viewModel) == "setup")
        await viewModel.finishSetup()

        #expect(env.gateway.calls.contains("setSettings"))
        #expect(step(viewModel) == "mark")
    }

    @Test func settingsThisPersonChoseNeverShowTheMoment() async {
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)
        let env = GamesTestEnvironment(state: state, hasSeenSettings: false)
        let viewModel = viewModel(env)

        await viewModel.load()
        viewModel.open(ludo)

        #expect(viewModel.screen == .hub)
        #expect(viewModel.destinationToOpen == ludo)
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
        // The Home tab shows the game the partner is in.
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
        #expect(viewModel.notice == .couldNotSaveSettings(.other))
    }

    @Test func withNothingCachedAndAFailedReadTheTabSaysWhy() async {
        let env = GamesTestEnvironment(state: nil)
        env.gateway.fail("load")
        env.gateway.fail("overview")
        let viewModel = viewModel(env)

        await viewModel.load()

        // The scripted failure is not a lost connection, so the tab must not say offline.
        #expect(viewModel.screen == .unavailable(.other))
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

@MainActor
extension GamesViewModelTests {
    @Test func aGamesStoreChangeReloadsTheHubEvenInABurst() async {
        let env = GamesTestEnvironment(state: nil)
        func overview(_ settings: RemoteGameSettings?) -> RemoteGamesOverview {
            RemoteGamesOverview(
                userID: GameFixture.me,
                partnerUserID: GameFixture.partner,
                coupleID: DeveloperScenarioFixture.coupleID,
                settings: settings,
                presence: []
            )
        }
        await env.cache.saveOverview(overview(nil), ownerUserID: GameFixture.me)
        let viewModel = viewModel(env)
        await viewModel.load()
        #expect(viewModel.settings == nil)
        let observing = Task { await viewModel.observeStoreChanges() }
        defer { observing.cancel() }

        await env.cache.saveOverview(overview(GameFixture.settings()), ownerUserID: GameFixture.me)
        // The observer subscribes in a task, so a write posted before it listens is lost.
        // Posting again each poll also makes a burst.
        #expect(await waitUntil {
            for _ in 0..<5 {
                LocalStoreChanges.post(.games, ownerUserID: GameFixture.me)
            }
            return await viewModel.settings == GameFixture.settings()
        })
    }
}
