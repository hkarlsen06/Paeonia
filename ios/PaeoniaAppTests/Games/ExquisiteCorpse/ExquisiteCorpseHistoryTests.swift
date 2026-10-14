import Foundation
import Testing
@testable import PaeoniaApp

// The protocol is async, and this stand-in answers without awaiting.
// swiftlint:disable async_without_await

/// Answers "Our creatures" pages from a list and records every request. A class with a
/// lock, so tests read its record without `await`. Every other call fails.
final class ScriptedCorpseHistoryGateway: ExquisiteCorpseGateway, @unchecked Sendable {
    struct Failure: Error {}

    struct Request: Equatable {
        var starredOnly: Bool
        var beforeFigureNumber: Int?
        var limit: Int
    }

    private let lock = NSLock()
    private var figures: [RemoteExquisiteCorpseFigure] = []
    private var recordedRequests: [Request] = []
    private var isFailing = false

    var requests: [Request] { lock.withLock { recordedRequests } }

    func setFigures(_ figures: [RemoteExquisiteCorpseFigure]) {
        lock.withLock { self.figures = figures }
    }

    func setFailing(_ failing: Bool) {
        lock.withLock { isFailing = failing }
    }

    func loadExquisiteCorpseHistory(
        starredOnly: Bool,
        beforeFigureNumber: Int?,
        limit: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage {
        let (figures, failing) = lock.withLock {
            recordedRequests.append(
                Request(starredOnly: starredOnly, beforeFigureNumber: beforeFigureNumber, limit: limit)
            )
            return (self.figures, isFailing)
        }
        if failing { throw Failure() }
        return ExquisiteCorpseDeveloperFixture.historyPage(
            from: figures,
            starredOnly: starredOnly,
            before: beforeFigureNumber,
            limit: limit
        )
    }

    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult {
        throw Failure()
    }

    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState {
        throw Failure()
    }

    func submitExquisiteCorpsePart(
        _: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID _: UUID,
        stripAssetID _: UUID?,
        operation _: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult {
        throw Failure()
    }

    func markExquisiteCorpseRevealSeen(figureID _: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult {
        throw Failure()
    }

    func setExquisiteCorpseStar(figureID _: UUID, starred _: Bool) async throws -> RemoteExquisiteCorpseStarResult {
        throw Failure()
    }
}

// swiftlint:enable async_without_await

/// "Our creatures": paging, the filters, the cache and the stars.
@MainActor
struct ExquisiteCorpseHistoryTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private let environment = ExquisiteCorpseTestEnvironment(state: nil)
    private let gateway = ScriptedCorpseHistoryGateway()

    /// Twelve finished creatures, newest first. The ones in `starred` are starred.
    private func figures(starred: Set<Int> = [10, 7, 4]) -> [RemoteExquisiteCorpseFigure] {
        (1...12).reversed().map { Fixture.figure($0, revealSeen: true, starred: starred.contains($0)) }
    }

    private func makeHistory(
        pageSize: Int = 30,
        figures: [RemoteExquisiteCorpseFigure]? = nil
    ) -> ExquisiteCorpseHistoryViewModel {
        gateway.setFigures(figures ?? self.figures())
        var dependencies = environment.dependencies(withRoom: false)
        dependencies.exquisiteCorpseGateway = gateway
        let stars = GameStars(source: .exquisiteCorpse(cache: environment.cache), dependencies: dependencies) {
            Fixture.me
        }
        return ExquisiteCorpseHistoryViewModel(
            dependencies: dependencies,
            stars: stars,
            participants: ExquisiteCorpseTestEnvironment.participants,
            pageSize: pageSize
        )
    }

    // MARK: Reading

    @Test func theFirstPageLoadsFromTheServer() async {
        let history = makeHistory(pageSize: 5)

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleFigures.map(\.number) == [12, 11, 10, 9, 8])
        #expect(history.hasMore)
        #expect(history.creatureCount == 12)
        #expect(gateway.requests == [.init(starredOnly: false, beforeFigureNumber: nil, limit: 5)])
    }

    @Test func theFirstPageIsKeptForTheNextOpen() async {
        let first = makeHistory(pageSize: 5)
        await first.refresh()

        // The next open is offline.
        let second = makeHistory(pageSize: 5)
        gateway.setFailing(true)
        await second.refresh()

        #expect(second.phase == .loaded)
        #expect(second.visibleFigures.map(\.number) == [12, 11, 10, 9, 8])
        #expect(second.creatureCount == 12)
    }

    @Test func offlineWithNothingCachedSaysSoAndTryAgainLoads() async {
        let history = makeHistory()
        gateway.setFailing(true)

        await history.refresh()
        #expect(history.phase == .offline)

        gateway.setFailing(false)
        await history.retry()
        #expect(history.phase == .loaded)
        #expect(history.visibleFigures.count == 12)
    }

    @Test func aCoupleWithoutCreaturesSeesTheEmptyState() async {
        let history = makeHistory(figures: [])

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.isEmpty)
        #expect(history.hasNoCreatures)
        #expect(history.creatureCount == 0)
    }

    @Test func aFailedReadKeepsTheListOnScreen() async {
        let history = makeHistory(pageSize: 5)
        await history.refresh()
        gateway.setFailing(true)

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleFigures.count == 5)
    }

    // MARK: Paging

    @Test func olderPagesLoadUntilTheEnd() async throws {
        let history = makeHistory(pageSize: 5)
        await history.refresh()

        await history.loadMoreIfNeeded(after: try #require(history.visibleFigures.last))
        #expect(history.visibleFigures.count == 10)
        #expect(history.hasMore)

        await history.loadMoreIfNeeded(after: try #require(history.visibleFigures.last))
        #expect(history.visibleFigures.map(\.number) == Array((1...12).reversed()))
        #expect(!history.hasMore)
        #expect(gateway.requests.map(\.beforeFigureNumber) == [nil, 8, 3])
    }

    @Test func aCellFarFromTheEndLoadsNothing() async throws {
        let history = makeHistory(pageSize: 12)
        await history.refresh()
        let first = try #require(history.visibleFigures.first)

        await history.loadMoreIfNeeded(after: first)

        #expect(gateway.requests.count == 1)
    }

    @Test func aFailedPageShowsRetryAndTheNextTryAddsTheCreatures() async throws {
        let history = makeHistory(pageSize: 5)
        await history.refresh()
        gateway.setFailing(true)

        await history.loadMoreIfNeeded(after: try #require(history.visibleFigures.last))
        #expect(history.loadMoreFailed)
        #expect(history.visibleFigures.count == 5)

        // A cell that shows up again does not ask a second time until the person does.
        await history.loadMoreIfNeeded(after: try #require(history.visibleFigures.last))
        #expect(gateway.requests.count == 2)

        gateway.setFailing(false)
        await history.retryLoadMore()
        #expect(!history.loadMoreFailed)
        #expect(history.visibleFigures.count == 10)
    }

    @Test func refreshingAfterScrollingKeepsTheOlderCreatures() {
        var listing = ExquisiteCorpseHistoryListing()
        listing.refresh(with: page(before: nil, limit: 3), pageSize: 3)
        listing.append(page(before: 10, limit: 3))
        let cursor = listing.nextCursor
        #expect(listing.figures.count == 6)

        listing.refresh(with: page(before: nil, limit: 3), pageSize: 3)

        #expect(listing.figures.map(\.number) == [12, 11, 10, 9, 8, 7])
        #expect(listing.nextCursor == cursor)
    }

    @Test func refreshingStartsOverWhenTheNewPageDoesNotReachTheOlderCreatures() {
        var listing = ExquisiteCorpseHistoryListing()
        listing.refresh(with: page(before: 10, limit: 3), pageSize: 3)
        listing.append(page(before: 7, limit: 3))
        #expect(listing.figures.count == 6)

        let first = page(before: nil, limit: 2)
        listing.refresh(with: first, pageSize: 3)

        #expect(listing.figures.map(\.number) == first.figures.map(\.number))
        #expect(listing.nextCursor == first.nextBeforeFigureNumber)
    }

    @Test func aCreatureNeverAppearsTwiceWhenPagesOverlap() {
        var listing = ExquisiteCorpseHistoryListing()
        listing.refresh(with: page(before: nil, limit: 4), pageSize: 4)

        listing.append(page(before: 11, limit: 4))

        #expect(listing.figures.map(\.number) == [12, 11, 10, 9, 8, 7])
    }

    private func page(before: Int?, limit: Int) -> RemoteExquisiteCorpseHistoryPage {
        ExquisiteCorpseDeveloperFixture.historyPage(from: figures(), starredOnly: false, before: before, limit: limit)
    }

    // MARK: Filters and stars

    @Test func theStarredFilterShowsOnlyMyStars() async {
        let history = makeHistory()
        history.filter = .starred

        await history.refresh()

        #expect(history.visibleFigures.map(\.number) == [10, 7, 4])
        #expect(gateway.requests.first?.starredOnly == true)
        #expect(!history.isEmpty)
    }

    @Test func aCreatureLeavesTheStarredListTheMomentItIsUnstarred() async throws {
        let history = makeHistory()
        history.filter = .starred
        await history.refresh()
        let first = try #require(history.visibleFigures.first)

        await history.stars.setStarred(false, id: first.id)

        #expect(!history.visibleFigures.contains { $0.id == first.id })
    }

    @Test func aCreatureStarredFromAllJoinsTheStarredList() async throws {
        let history = makeHistory()
        await history.refresh()
        history.filter = .starred
        await history.refresh()
        let unstarred = try #require(figures().first { !$0.starredByMe })

        await history.stars.setStarred(true, id: unstarred.id)

        #expect(history.visibleFigures.contains { $0.id == unstarred.id })
        // Newest first, whichever list a creature came from.
        let numbers = history.visibleFigures.map(\.number)
        #expect(numbers == numbers.sorted(by: >))
    }

    @Test func noStarsShowTheStarredEmptyStateNotTheNoCreaturesOne() async {
        let history = makeHistory(figures: figures(starred: []))
        await history.refresh()
        history.filter = .starred

        await history.refresh()

        #expect(history.isEmpty)
        #expect(!history.hasNoCreatures)
    }

    @Test func offlineTheStarredFilterFallsBackToTheCachedList() async {
        let first = makeHistory(pageSize: 12)
        await first.refresh()

        let second = makeHistory(pageSize: 12)
        gateway.setFailing(true)
        second.filter = .starred
        await second.refresh()

        #expect(second.phase == .loaded)
        #expect(second.visibleFigures.map(\.number) == [10, 7, 4])
    }

    @Test func theServersStarsReachTheStarStore() async throws {
        let history = makeHistory()

        await history.refresh()

        let starred = try #require(figures().first { $0.starredByMe })
        let unstarred = try #require(figures().first { !$0.starredByMe })
        #expect(history.stars.isStarred(starred.id))
        #expect(!history.stars.isStarred(unstarred.id))
    }

    // MARK: Names and the detail

    @Test func theCellNamesThePartner() {
        let history = makeHistory()

        #expect(history.partnerName == ExquisiteCorpseTestEnvironment.participants.partnerName)
    }

    @Test func aLoadedCreatureOpensItsDetailAndAnUnknownOneDoesNot() async {
        let history = makeHistory()
        #expect(history.makeDetail(figureID: Fixture.figureID(3)) == nil)

        await history.refresh()

        #expect(history.makeDetail(figureID: Fixture.figureID(3))?.figure.number == 3)
        #expect(history.makeDetail(figureID: UUID()) == nil)
    }

    @Test func aNewIdentityClearsTheList() async {
        let history = makeHistory()
        await history.refresh()
        #expect(history.creatureCount == 12)

        history.configure(participants: GameParticipants(currentUserID: Fixture.partner, coupleID: Fixture.couple))

        #expect(history.creatureCount == 0)
        #expect(history.phase == .loading)
    }
}
