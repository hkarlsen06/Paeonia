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

    @Test func finishingSetupSavesTheChoicesThenAsksForAMarkThenOpensTheGame() async {
        let env = GamesTestEnvironment(state: GameFixture.state(settings: nil, game: nil))
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

    @Test func thePartnerWhoArrivesLaterSeesWhatWasPickedOnceBeforeTheFirstGame() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(by: GameFixture.partner),
            game: nil
        )
        let env = GamesTestEnvironment(state: state)
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
        #expect(env.gateway.calls.contains("markSettingsSeen"))
        #expect(step(viewModel) == "mark")

        // A new view model on the same cache opens games at once.
        let again = self.viewModel(env)
        await again.load()
        again.open(ludo)
        #expect(step(again) == "none")
        #expect(again.destinationToOpen == ludo)
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
