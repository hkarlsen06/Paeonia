import Foundation
import Testing
@testable import PaeoniaApp

extension ScriptedGamesGateway {
    struct HistoryRequest: Equatable {
        var starredOnly: Bool
        var beforeRoundNumber: Int?
        var limit: Int
    }

    struct StarWrite: Equatable {
        var roundID: UUID
        var starred: Bool
    }
}

/// "Our drawings": paging, the filters, and the cache.
@MainActor
struct DrawAndGuessHistoryTests {
    private let environment = GamesTestEnvironment(state: nil)

    private var rounds: [RemoteDrawAndGuessHistoryRound] {
        DeveloperGamesFixture.historyRounds()
    }

    private func makeHistory(
        pageSize: Int = 30,
        rounds: [RemoteDrawAndGuessHistoryRound]? = nil
    ) -> DrawAndGuessHistoryViewModel {
        environment.gateway.setHistory(rounds ?? self.rounds)
        environment.gateway.setRecords(DeveloperGamesFixture.records)
        let dependencies = environment.dependencies()
        let stars = GameStars(source: .drawAndGuess(cache: dependencies.cache), dependencies: dependencies) {
            GameFixture.me
        }
        return DrawAndGuessHistoryViewModel(
            dependencies: dependencies,
            stars: stars,
            participants: GameFixture.participants,
            pageSize: pageSize
        )
    }

    // MARK: Reading

    @Test func theFirstPageAndTheRecordsLoadFromTheServer() async {
        let history = makeHistory(pageSize: 5)

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleRounds.map(\.roundNumber) == [12, 11, 10, 9, 8])
        #expect(history.hasMore)
        #expect(history.myRecords?.userID == GameFixture.me)
        #expect(history.partnerRecords?.userID == GameFixture.partner)
        #expect(environment.gateway.historyRequests == [.init(starredOnly: false, beforeRoundNumber: nil, limit: 5)])
    }

    @Test func theFirstPageAndTheRecordsAreKeptForTheNextOpen() async {
        let first = makeHistory(pageSize: 5)
        await first.refresh()

        // The next open is offline.
        let second = makeHistory(pageSize: 5)
        environment.gateway.fail("history")
        environment.gateway.fail("records")
        await second.refresh()

        #expect(second.phase == .loaded)
        #expect(second.visibleRounds.map(\.roundNumber) == [12, 11, 10, 9, 8])
        #expect(second.myRecords == DeveloperGamesFixture.records.records(for: GameFixture.me))
    }

    // MARK: Paging

    @Test func olderPagesLoadUntilTheEnd() async throws {
        let history = makeHistory(pageSize: 5)
        await history.refresh()

        await history.loadMoreIfNeeded(after: try #require(history.visibleRounds.last))
        #expect(history.visibleRounds.count == 10)
        #expect(history.hasMore)

        await history.loadMoreIfNeeded(after: try #require(history.visibleRounds.last))
        #expect(history.visibleRounds.map(\.roundNumber) == Array((1...12).reversed()))
        #expect(!history.hasMore)
        #expect(environment.gateway.historyRequests.map(\.beforeRoundNumber) == [nil, 8, 3])
    }

    @Test func refreshingAfterScrollingKeepsTheOlderRounds() {
        var listing = DrawAndGuessHistoryListing()
        listing.refresh(with: DeveloperGamesFixture.historyPage(starredOnly: false, before: nil, limit: 3), pageSize: 3)
        listing.append(DeveloperGamesFixture.historyPage(starredOnly: false, before: 10, limit: 3))
        let cursor = listing.nextCursor
        #expect(listing.rounds.count == 6)

        listing.refresh(with: DeveloperGamesFixture.historyPage(starredOnly: false, before: nil, limit: 3), pageSize: 3)

        #expect(listing.rounds.map(\.roundNumber) == [12, 11, 10, 9, 8, 7])
        #expect(listing.nextCursor == cursor)
    }

    @Test func refreshingStartsOverWhenTheNewPageDoesNotReachTheOlderRounds() {
        var listing = DrawAndGuessHistoryListing()
        listing.refresh(with: DeveloperGamesFixture.historyPage(starredOnly: false, before: 10, limit: 3), pageSize: 3)
        listing.append(DeveloperGamesFixture.historyPage(starredOnly: false, before: 7, limit: 3))
        #expect(listing.rounds.count == 6)

        let first = DeveloperGamesFixture.historyPage(starredOnly: false, before: nil, limit: 2)
        listing.refresh(with: first, pageSize: 3)

        #expect(listing.rounds.map(\.roundNumber) == first.rounds.map(\.roundNumber))
        #expect(listing.nextCursor == first.nextBeforeRoundNumber)
    }

    @Test func aRoundNeverAppearsTwiceWhenPagesOverlap() {
        var listing = DrawAndGuessHistoryListing()
        listing.refresh(with: DeveloperGamesFixture.historyPage(starredOnly: false, before: nil, limit: 4), pageSize: 4)

        listing.append(DeveloperGamesFixture.historyPage(starredOnly: false, before: 11, limit: 4))

        #expect(listing.rounds.map(\.roundNumber) == [12, 11, 10, 9, 8, 7])
    }

    // MARK: Filters and stars

    @Test func theStarredFilterShowsOnlyMyStars() async {
        let history = makeHistory()
        history.filter = .starred

        await history.refresh()

        let expected = rounds.filter(\.starredByMe).map(\.roundNumber)
        #expect(history.visibleRounds.map(\.roundNumber) == expected)
        #expect(environment.gateway.historyRequests.first?.starredOnly == true)
        #expect(!history.isEmpty)
    }
}
