import Foundation
import Testing
@testable import PaeoniaApp

/// "Our stories": paging, the filters, and the cache.
@MainActor
struct StoryChainHistoryTests {
    private typealias Fixture = StoryChainFixture
    private typealias ViewModel = StoryChainHistoryViewModel

    private let environment = StoryChainDataEnvironment()

    private let participants = GameParticipants(
        currentUserID: Fixture.me,
        coupleID: Fixture.couple,
        partnerName: "Robin",
        currentName: "Alex"
    )

    /// Twelve finished stories. Every fourth one is starred.
    private var items: [RemoteStoryChainHistoryItem] {
        (1...12).map { storyChainHistoryItem($0) }
    }

    private func makeHistory(
        pageSize: Int = 30,
        items: [RemoteStoryChainHistoryItem]? = nil
    ) -> (history: ViewModel, favorites: FavoritesStore) {
        let starredIDs = (1...12).filter { $0.isMultiple(of: 4) }.map(storyChainHistoryID)
        environment.gateway.setHistory(items ?? self.items)
        environment.gateway.setStarredStories(Set(starredIDs))
        let favorites = FavoritesStore.preloaded(
            ownerUserID: Fixture.me,
            favorites: starredIDs.map { FavoriteRef(target: .storyChainStory($0), createdAt: Fixture.now) }
        )
        let history = ViewModel(
            dependencies: environment.dependencies(favorites: favorites),
            participants: participants,
            pageSize: pageSize
        )
        return (history, favorites)
    }

    // MARK: Reading

    @Test func theFirstPageLoadsFromTheServer() async {
        let (history, _) = makeHistory()
        #expect(history.phase == .loading)

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleItems.map(\.storyNumber) == Array((1...12).reversed()))
        #expect(!history.hasMore)
        #expect(environment.gateway.historyRequests == [.init(starredOnly: false, beforeStoryNumber: nil, limit: 30)])
    }

    @Test func theCachedPageShowsWhenTheServerCannotBeReached() async {
        let (first, _) = makeHistory()
        await first.refresh()

        environment.gateway.fail("history")
        let (second, _) = makeHistory()
        await second.refresh()

        #expect(second.phase == .loaded)
        #expect(second.visibleItems.count == 12)
    }

    @Test func offlineWithNothingCachedSaysSoAndTryAgainLoads() async {
        environment.gateway.fail("history")
        let (history, _) = makeHistory()

        await history.refresh()
        #expect(history.phase == .failed(.other))

        environment.gateway.unfail("history")
        await history.retry()
        #expect(history.phase == .loaded)
        #expect(history.visibleItems.count == 12)
    }

    @Test func aFailedReadKeepsTheListOnScreen() async {
        let (history, _) = makeHistory()
        await history.refresh()

        environment.gateway.fail("history")
        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleItems.count == 12)
    }

    // MARK: Paging

    @Test func olderPagesLoadUntilTheEnd() async throws {
        let (history, _) = makeHistory(pageSize: 5)
        await history.refresh()
        #expect(history.visibleItems.count == 5)
        #expect(history.hasMore)

        await history.loadMoreIfNeeded(after: try #require(history.visibleItems.last))
        #expect(history.visibleItems.count == 10)
        await history.loadMoreIfNeeded(after: try #require(history.visibleItems.last))

        #expect(history.visibleItems.map(\.storyNumber) == Array((1...12).reversed()))
        #expect(!history.hasMore)
        #expect(environment.gateway.historyRequests.map(\.beforeStoryNumber) == [nil, 8, 3])
    }

    @Test func aFailedPageShowsRetryAndTheNextTryAddsTheStories() async throws {
        let (history, _) = makeHistory(pageSize: 5)
        await history.refresh()
        let last = try #require(history.visibleItems.last)

        environment.gateway.fail("history")
        await history.loadMoreIfNeeded(after: last)
        #expect(history.loadMoreFailed)
        #expect(history.visibleItems.count == 5)

        // A row that appears again does not ask again until the person taps retry.
        await history.loadMoreIfNeeded(after: last)
        #expect(environment.gateway.historyRequests.count == 2)

        environment.gateway.unfail("history")
        await history.retryLoadMore()
        #expect(!history.loadMoreFailed)
        #expect(history.visibleItems.count == 10)
    }

    // MARK: Favorites

    @Test func theStarredFilterShowsOnlyMyStars() async {
        let (history, _) = makeHistory()
        history.filter = .starred

        await history.refresh()

        #expect(history.visibleItems.map(\.storyNumber) == [12, 8, 4])
        #expect(environment.gateway.historyRequests.first?.starredOnly == true)
    }

    @Test func aStoryLeavesTheStarredListTheMomentItIsUnstarred() async throws {
        let (history, favorites) = makeHistory()
        history.filter = .starred
        await history.refresh()
        let eight = try #require(history.visibleItems.first { $0.storyNumber == 8 })

        await favorites.setFavorite(false, target: .storyChainStory(eight.id))

        #expect(history.visibleItems.map(\.storyNumber) == [12, 4])
    }

    @Test func aStoryStarredFromAllJoinsTheStarredList() async throws {
        let (history, favorites) = makeHistory()
        await history.refresh()
        history.filter = .starred
        await history.refresh()
        let nine = try #require(history.item(withID: storyChainHistoryItem(9).id))

        await favorites.setFavorite(true, target: .storyChainStory(nine.id))

        #expect(history.visibleItems.map(\.storyNumber) == [12, 9, 8, 4])
    }

    @Test func offlineTheStarredFilterFallsBackToTheCachedList() async {
        let (history, _) = makeHistory()
        await history.refresh()

        environment.gateway.fail("history")
        history.filter = .starred
        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.visibleItems.map(\.storyNumber) == [12, 8, 4])
    }

    // MARK: One story

    @Test func aFinishedStoryInTheCachedStateOpensWithoutTheServer() async throws {
        let story = finishedStoryChainStory()
        let env = StoryChainDataEnvironment(
            state: Fixture.state(
                Fixture.game(.choosingOpening, turn: Fixture.me, current: story.id),
                current: story
            )
        )
        let history = ViewModel(dependencies: env.dependencies(), participants: participants)

        let loaded = try await history.loadStory(id: story.id)

        #expect(loaded == story)
        #expect(!env.gateway.calls.contains("loadStory"))
    }

    @Test func anOlderStoryComesFromTheServer() async throws {
        let older = finishedStoryChainStory(id: UUID(), number: 2)
        environment.gateway.setStoryToLoad(older)
        let (history, _) = makeHistory()

        let loaded = try await history.loadStory(id: older.id)

        #expect(loaded == older)
    }

    @Test func aStoryThatIsStillBeingWrittenInTheCachedStateIsReadFromTheServer() async throws {
        let writing = Fixture.story(.writing, lines: Fixture.lines(3, starter: Fixture.me))
        let env = StoryChainDataEnvironment(
            state: Fixture.state(Fixture.game(.writing, turn: Fixture.partner), current: writing)
        )
        let finished = finishedStoryChainStory()
        env.gateway.setStoryToLoad(finished)
        let history = ViewModel(dependencies: env.dependencies(), participants: participants)

        #expect(try await history.loadStory(id: finished.id) == finished)
    }

    @Test func aStoryNobodyHasIsNilAndOneThatCannotBeReadThrows() async throws {
        let (history, _) = makeHistory()
        #expect(try await history.loadStory(id: UUID()) == nil)

        let known = finishedStoryChainStory(id: UUID(), number: 2)
        environment.gateway.setStoryToLoad(known)
        environment.gateway.fail("loadStory")
        await #expect(throws: (any Error).self) {
            try await history.loadStory(id: known.id)
        }
    }

    // MARK: People

    @Test func aChangeOfPersonClearsWhatWasLoaded() async {
        let (history, _) = makeHistory()
        await history.refresh()

        let otherPerson = GameParticipants(
            currentUserID: Fixture.partner,
            coupleID: Fixture.couple,
            partnerName: "Alex"
        )
        history.configure(participants: otherPerson)

        #expect(history.phase == .loading)
        #expect(history.visibleItems.isEmpty)
        #expect(history.partnerName == "Alex")
    }
}
