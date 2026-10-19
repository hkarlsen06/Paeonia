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
}
