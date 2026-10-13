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

/// A copy of a history round with a few fields changed. A new id is made when the round number moves.
func movedHistoryRound(
    _ round: RemoteDrawAndGuessHistoryRound,
    by offset: Int = 0,
    solveMs: Int? = nil,
    starred: Bool? = nil
) -> RemoteDrawAndGuessHistoryRound {
    RemoteDrawAndGuessHistoryRound(
        id: offset == 0 ? round.id : UUID(),
        roundNumber: round.roundNumber + offset,
        drawerUserID: round.drawerUserID,
        guesserUserID: round.guesserUserID,
        word: round.word,
        difficulty: round.difficulty,
        points: round.points,
        state: round.state,
        drawingMediaAssetID: round.drawingMediaAssetID,
        solveMs: solveMs ?? round.solveMs,
        speedBonus: round.speedBonus,
        firstTryBonus: round.firstTryBonus,
        hintsUsed: round.hintsUsed,
        attemptCount: round.attemptCount,
        guesserReaction: round.guesserReaction,
        personalBest: round.personalBest,
        starredByMe: starred ?? round.starredByMe,
        startedAt: round.startedAt,
        endedAt: round.endedAt
    )
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
        let stars = DrawAndGuessStars(dependencies: dependencies) { GameFixture.me }
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

    @Test func offlineWithNothingCachedSaysSoAndTryAgainLoads() async {
        let history = makeHistory()
        environment.gateway.fail("history")

        await history.refresh()
        #expect(history.phase == .offline)

        environment.gateway.unfail("history")
        await history.retry()
        #expect(history.phase == .loaded)
        #expect(history.visibleRounds.count == 12)
    }

    @Test func aCoupleWithoutDrawingsSeesTheEmptyState() async {
        let history = makeHistory(rounds: [])

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.isEmpty)
        #expect(history.hasNoDrawings)
    }

    @Test func aFailedReadKeepsTheListOnScreen() async {
        let history = makeHistory(pageSize: 5)
        await history.refresh()
        environment.gateway.fail("history")

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleRounds.count == 5)
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

    @Test func aCellFarFromTheEndLoadsNothing() async throws {
        let history = makeHistory(pageSize: 12, rounds: rounds + rounds.map { movedHistoryRound($0, by: -12) })
        await history.refresh()

        await history.loadMoreIfNeeded(after: try #require(history.visibleRounds.first))

        #expect(environment.gateway.historyRequests.count == 1)
    }

    @Test func aFailedPageShowsRetryAndTheNextTryAddsTheRounds() async throws {
        let history = makeHistory(pageSize: 5)
        await history.refresh()
        environment.gateway.fail("history")

        await history.loadMoreIfNeeded(after: try #require(history.visibleRounds.last))
        #expect(history.loadMoreFailed)
        #expect(history.visibleRounds.count == 5)

        // A cell that shows up again does not ask a second time until the person does.
        await history.loadMoreIfNeeded(after: try #require(history.visibleRounds.last))
        #expect(environment.gateway.historyRequests.count == 2)

        environment.gateway.unfail("history")
        await history.retryLoadMore()
        #expect(!history.loadMoreFailed)
        #expect(history.visibleRounds.count == 10)
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

    @Test func aDrawingLeavesTheStarredListTheMomentItIsUnstarred() async throws {
        let history = makeHistory()
        history.filter = .starred
        await history.refresh()
        let first = try #require(history.visibleRounds.first)

        await history.stars.setStarred(false, roundID: first.id)

        #expect(!history.visibleRounds.contains { $0.id == first.id })
    }

    @Test func aDrawingStarredFromAllJoinsTheStarredList() async throws {
        let history = makeHistory()
        await history.refresh()
        history.filter = .starred
        await history.refresh()
        let unstarred = try #require(rounds.first { !$0.starredByMe })

        await history.stars.setStarred(true, roundID: unstarred.id)

        #expect(history.visibleRounds.contains { $0.id == unstarred.id })
        // Newest first, whichever list a drawing came from.
        let numbers = history.visibleRounds.map(\.roundNumber)
        #expect(numbers == numbers.sorted(by: >))
    }

    @Test func noStarsShowTheStarredEmptyStateNotTheNoDrawingsOne() async {
        let none = rounds.map { unstarred($0) }
        let history = makeHistory(rounds: none)
        await history.refresh()
        history.filter = .starred

        await history.refresh()

        #expect(history.isEmpty)
        #expect(!history.hasNoDrawings)
    }

    @Test func offlineTheStarredFilterFallsBackToTheCachedList() async {
        let first = makeHistory(pageSize: 12)
        await first.refresh()

        let second = makeHistory(pageSize: 12)
        environment.gateway.fail("history")
        environment.gateway.fail("records")
        second.filter = .starred
        await second.refresh()

        #expect(second.phase == .loaded)
        #expect(second.visibleRounds.map(\.roundNumber) == rounds.filter(\.starredByMe).map(\.roundNumber))
    }

    @Test func theServersStarsReachTheStarStore() async throws {
        let history = makeHistory()

        await history.refresh()

        let starred = try #require(rounds.first(where: \.starredByMe))
        let unstarredRound = try #require(rounds.first { !$0.starredByMe })
        #expect(history.stars.isStarred(starred.id))
        #expect(!history.stars.isStarred(unstarredRound.id))
    }

    // MARK: Names and the hub link

    @Test func theCellNamesThePartnerOrYou() async throws {
        let history = makeHistory()
        await history.refresh()
        let mine = try #require(rounds.first { $0.drawerUserID == GameFixture.me })
        let theirs = try #require(rounds.first { $0.drawerUserID == GameFixture.partner })

        #expect(history.drawerName(of: theirs) == GameFixture.participants.partnerName)
        #expect(history.drawerName(of: mine) != GameFixture.participants.partnerName)
    }

    @Test func theHubLinkNeedsAFinishedDrawing() {
        let drawn = GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)
        let stillDrawing = GameFixture.round(state: .drawing, drawer: GameFixture.partner)

        let withDrawing = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            recentRounds: [drawn]
        )
        let without = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: stillDrawing
        )

        #expect(withDrawing.hasFinishedDrawing)
        #expect(!without.hasFinishedDrawing)
    }

    // MARK: Helpers

    private func unstarred(_ round: RemoteDrawAndGuessHistoryRound) -> RemoteDrawAndGuessHistoryRound {
        movedHistoryRound(round, starred: false)
    }
}
