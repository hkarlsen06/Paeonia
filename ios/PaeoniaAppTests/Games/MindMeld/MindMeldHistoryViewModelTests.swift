import Foundation
import Testing
@testable import PaeoniaApp

/// "Our melds": the cached first page shows at once, the server's page replaces
/// it, and older games load 30 at a time.
@MainActor
struct MindMeldHistoryViewModelTests {
    private let fixtures = MindMeldFixtures()

    /// `count` finished games, numbered 1 to `count`. The gateway lists them newest first.
    private func environment(games count: Int, cached: Bool = false) async -> MindMeldTestEnvironment {
        let env = MindMeldTestEnvironment(state: nil)
        let games = (1...max(count, 1)).reversed().map { fixtures.historyGame(number: $0) }
        env.gateway.setHistory(count == 0 ? [] : games)
        if cached {
            await env.cache.saveHistoryFirstPage(
                RemoteMindMeldHistoryPage(
                    games: Array(games.prefix(30)),
                    nextBeforeGameNumber: nil,
                    stats: RemoteMindMeldStats(melds: 2, fewestRounds: 3, games: 5)
                ),
                ownerUserID: GameFixture.me
            )
        }
        return env
    }

    private func viewModel(_ env: MindMeldTestEnvironment) -> MindMeldHistoryViewModel {
        MindMeldHistoryViewModel(dependencies: env.dependencies(), participants: GameFixture.participants)
    }

    @Test func theFirstPageLoadsAndIsCached() async {
        let env = await environment(games: 70)
        let viewModel = viewModel(env)
        #expect(viewModel.isLoading)

        await viewModel.load()

        #expect(!viewModel.isLoading)
        #expect(!viewModel.loadFailed)
        #expect(viewModel.games.count == 30)
        #expect(viewModel.games.first?.gameNumber == 70)
        #expect(viewModel.hasMore)
        #expect(env.gateway.historyRequests == [.init(beforeGameNumber: nil, limit: 30)])
        let cached = await env.cache.document(ownerUserID: GameFixture.me).history
        #expect(cached?.games.count == 30)
    }

    @Test func theCachedPageStaysWhenTheServerCannotBeReached() async {
        let env = await environment(games: 5, cached: true)
        env.gateway.fail("history")
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.games.count == 5)
        #expect(!viewModel.loadFailed)
        #expect(!viewModel.isLoading)
        #expect(viewModel.stats?.melds == 2)
    }

    @Test func withNothingCachedAFailedReadSaysSo() async {
        let env = await environment(games: 5)
        env.gateway.fail("history")
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.loadFailed)
        #expect(!viewModel.isLoading)
        #expect(viewModel.games.isEmpty)

        env.gateway.unfail("history")
        await viewModel.load()

        #expect(!viewModel.loadFailed)
        #expect(viewModel.games.count == 5)
    }

    @Test func noFinishedGamesIsAnEmptyListNotAFailure() async {
        let env = await environment(games: 0)
        let viewModel = viewModel(env)

        await viewModel.load()

        #expect(viewModel.games.isEmpty)
        #expect(!viewModel.loadFailed)
        #expect(!viewModel.hasMore)
        #expect(!viewModel.isLoading)
    }

    @Test func olderGamesLoadWhenARowNearTheEndAppears() async {
        let env = await environment(games: 70)
        let viewModel = viewModel(env)
        await viewModel.load()

        // The top of the list does not ask for more.
        await viewModel.loadMoreIfNeeded(after: viewModel.games[0])
        #expect(viewModel.games.count == 30)

        await viewModel.loadMoreIfNeeded(after: viewModel.games[24])
        #expect(viewModel.games.count == 60)
        #expect(viewModel.hasMore)
        #expect(env.gateway.historyRequests.last == .init(beforeGameNumber: 41, limit: 30))

        await viewModel.loadMoreIfNeeded(after: viewModel.games[54])
        #expect(viewModel.games.count == 70)
        #expect(!viewModel.hasMore)
        #expect(Set(viewModel.games.map(\.id)).count == 70)
    }

    @Test func aFailedPageCanBeTriedAgain() async {
        let env = await environment(games: 40)
        let viewModel = viewModel(env)
        await viewModel.load()
        env.gateway.fail("history")

        await viewModel.loadMoreIfNeeded(after: viewModel.games[29])
        #expect(viewModel.loadMoreFailed)
        #expect(viewModel.games.count == 30)

        // A failed page does not ask again by itself.
        let requests = env.gateway.historyRequests.count
        await viewModel.loadMoreIfNeeded(after: viewModel.games[29])
        #expect(env.gateway.historyRequests.count == requests)

        env.gateway.unfail("history")
        await viewModel.retryLoadMore()

        #expect(!viewModel.loadMoreFailed)
        #expect(viewModel.games.count == 40)
        #expect(!viewModel.hasMore)
    }

    @Test func reloadingKeepsTheOlderGamesThePersonScrolledTo() async {
        let env = await environment(games: 70)
        let viewModel = viewModel(env)
        await viewModel.load()
        await viewModel.loadMoreIfNeeded(after: viewModel.games[24])
        #expect(viewModel.games.count == 60)

        await viewModel.load()

        #expect(viewModel.games.count == 60)
        #expect(viewModel.games.first?.gameNumber == 70)
        #expect(viewModel.hasMore)
    }

    @Test func aNewGameAppearsAtTheTopOfTheList() async {
        let env = await environment(games: 3)
        let viewModel = viewModel(env)
        await viewModel.load()
        #expect(viewModel.games.map(\.gameNumber) == [3, 2, 1])

        env.gateway.setHistory((1...4).reversed().map { fixtures.historyGame(number: $0) })
        await viewModel.load()

        #expect(viewModel.games.map(\.gameNumber) == [4, 3, 2, 1])
    }
}
