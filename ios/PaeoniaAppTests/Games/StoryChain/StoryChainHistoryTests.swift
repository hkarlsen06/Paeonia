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
        (1...12).map { storyChainHistoryItem($0, starred: $0.isMultiple(of: 4)) }
    }

    private func makeHistory(
        pageSize: Int = 30,
        items: [RemoteStoryChainHistoryItem]? = nil
    ) -> (history: ViewModel, stars: StoryChainStars) {
        environment.gateway.setHistory(items ?? self.items)
        let dependencies = environment.dependencies()
        let stars = StoryChainStars(dependencies: dependencies) { Fixture.me }
        let history = ViewModel(
            dependencies: dependencies,
            stars: stars,
            participants: participants,
            pageSize: pageSize
        )
        return (history, stars)
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

    @Test func theFirstPageIsKeptForTheNextOpen() async {
        let (history, _) = makeHistory()

        await history.refresh()

        let page = await environment.cache.document(ownerUserID: Fixture.me).historyFirstPage
        #expect(page?.stories.map(\.storyNumber) == Array((1...12).reversed()))
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

    @Test func aCoupleWithoutFinishedStoriesSeesTheEmptyState() async {
        let (history, _) = makeHistory(items: [])

        await history.refresh()

        #expect(history.phase == .loaded)
        #expect(history.isEmpty)
        #expect(history.hasNoStories)
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

    @Test func aRowFarFromTheEndLoadsNothing() async throws {
        let (history, _) = makeHistory(pageSize: 10, items: (1...30).map { storyChainHistoryItem($0) })
        await history.refresh()

        await history.loadMoreIfNeeded(after: try #require(history.visibleItems.first))

        #expect(history.visibleItems.count == 10)
        #expect(environment.gateway.historyRequests.count == 1)
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

    // MARK: Stars

    @Test func theStarredFilterShowsOnlyMyStars() async {
        let (history, _) = makeHistory()
        history.filter = .starred

        await history.refresh()

        #expect(history.visibleItems.map(\.storyNumber) == [12, 8, 4])
        #expect(environment.gateway.historyRequests.first?.starredOnly == true)
    }

    @Test func aStoryLeavesTheStarredListTheMomentItIsUnstarred() async throws {
        let (history, stars) = makeHistory()
        history.filter = .starred
        await history.refresh()
        let eight = try #require(history.visibleItems.first { $0.storyNumber == 8 })

        await stars.setStarred(false, storyID: eight.id)

        #expect(history.visibleItems.map(\.storyNumber) == [12, 4])
    }

    @Test func aStoryStarredFromAllJoinsTheStarredList() async throws {
        let (history, stars) = makeHistory()
        await history.refresh()
        history.filter = .starred
        await history.refresh()
        let nine = try #require(history.item(withID: storyChainHistoryItem(9).id))

        await stars.setStarred(true, storyID: nine.id)

        #expect(history.visibleItems.map(\.storyNumber) == [12, 9, 8, 4])
    }

    @Test func noStarsShowTheStarredEmptyStateNotTheNoStoriesOne() async {
        let (history, _) = makeHistory(items: (1...3).map { storyChainHistoryItem($0) })
        history.filter = .starred

        await history.refresh()
        history.filter = .all
        await history.refresh()
        history.filter = .starred

        #expect(history.isEmpty)
        #expect(!history.hasNoStories)
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

    @Test func theServersStarsReachTheStarStore() async {
        let (history, stars) = makeHistory()

        await history.refresh()

        #expect(stars.isStarred(storyChainHistoryItem(12).id))
        #expect(!stars.isStarred(storyChainHistoryItem(11).id))
    }

    // MARK: One story

    @Test func aFinishedStoryInTheCachedStateOpensWithoutTheServer() async throws {
        let story = finishedStoryChainStory(starred: true)
        let env = StoryChainDataEnvironment(
            state: Fixture.state(
                Fixture.game(.choosingOpening, turn: Fixture.me, current: story.id),
                current: story
            )
        )
        let dependencies = env.dependencies()
        let stars = StoryChainStars(dependencies: dependencies) { Fixture.me }
        let history = ViewModel(dependencies: dependencies, stars: stars, participants: participants)

        let loaded = try await history.loadStory(id: story.id)

        #expect(loaded == story)
        #expect(!env.gateway.calls.contains("loadStory"))
        #expect(stars.isStarred(story.id))
    }

    @Test func anOlderStoryComesFromTheServerWithItsStar() async throws {
        let older = finishedStoryChainStory(id: UUID(), number: 2, starred: true)
        environment.gateway.setStoryToLoad(older)
        let (history, stars) = makeHistory()

        let loaded = try await history.loadStory(id: older.id)

        #expect(loaded == older)
        #expect(stars.isStarred(older.id))
    }

    @Test func aStoryThatIsStillBeingWrittenInTheCachedStateIsReadFromTheServer() async throws {
        let writing = Fixture.story(.writing, lines: Fixture.lines(3, starter: Fixture.me))
        let env = StoryChainDataEnvironment(
            state: Fixture.state(Fixture.game(.writing, turn: Fixture.partner), current: writing)
        )
        let finished = finishedStoryChainStory()
        env.gateway.setStoryToLoad(finished)
        let dependencies = env.dependencies()
        let history = ViewModel(
            dependencies: dependencies,
            stars: StoryChainStars(dependencies: dependencies) { Fixture.me },
            participants: participants
        )

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

    @Test func newNamesDoNotClearWhatWasLoaded() async {
        let (history, _) = makeHistory()
        await history.refresh()

        history.configure(
            participants: GameParticipants(currentUserID: Fixture.me, coupleID: Fixture.couple, partnerName: "Robin R.")
        )

        #expect(history.visibleItems.count == 12)
        #expect(history.partnerName == "Robin R.")
    }
}
