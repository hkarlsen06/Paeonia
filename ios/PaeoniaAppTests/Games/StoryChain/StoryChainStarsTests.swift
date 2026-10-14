import Foundation
import Testing
@testable import PaeoniaApp

/// The private stars on finished stories: a star shows at once, waits in the
/// queue, keeps the last choice, and sits on top of what the server said.
@MainActor
struct StoryChainStarsTests {
    private typealias Fixture = StoryChainFixture

    private let environment = StoryChainDataEnvironment()
    private let storyID = UUID()

    private func makeStars(_ environment: StoryChainDataEnvironment? = nil) -> StoryChainStars {
        StoryChainStars(dependencies: (environment ?? self.environment).dependencies()) { Fixture.me }
    }

    private func enqueueStar(_ starred: Bool, sequence: Int64, storyID: UUID? = nil) async throws {
        try await environment.enqueue(
            .storyChainSetStar,
            StoryChainStarPayload(storyID: storyID ?? self.storyID, starred: starred, createdAt: Fixture.now),
            sequence: sequence
        )
    }

    // MARK: The store

    @Test func aStarShowsAtOnceAndWaitsInTheQueue() async throws {
        let stars = makeStars()

        await stars.setStarred(true, storyID: storyID)

        #expect(stars.isStarred(storyID))
        let queued = await environment.queued(.storyChainSetStar)
        #expect(queued.count == 1)
        let data = try #require(queued.first?.requestData)
        let payload = try JSONDecoder().decode(StoryChainStarPayload.self, from: data)
        #expect(payload.storyID == storyID)
        #expect(payload.starred)
        #expect(queued.first?.idempotencyScope == "story-chain-star:\(storyID.uuidString.lowercased())")
        // The server was not called: the write leaves with the next sync.
        #expect(environment.gateway.starWrites.isEmpty)
    }

    @Test func aStoryThatIsNotInTheHistoryYetCanBeStarred() async {
        let stars = makeStars()
        let justFinished = UUID()

        await stars.setStarred(true, storyID: justFinished)

        #expect(stars.isStarred(justFinished))
        #expect(!stars.isStarred(storyID))
    }

    @Test func theLastChoiceOfAStoryWins() async {
        let stars = makeStars()

        await stars.setStarred(true, storyID: storyID)
        await stars.setStarred(false, storyID: storyID)

        #expect(!stars.isStarred(storyID))
        #expect(await environment.queued(.storyChainSetStar).count == 2)
    }

    @Test func choosingTheValueThatAlreadyShowsQueuesNothing() async {
        let stars = makeStars()
        await environment.cache.saveStars([storyID: true], ownerUserID: Fixture.me)
        await stars.reload()

        await stars.setStarred(true, storyID: storyID)

        #expect(await environment.queued(.storyChainSetStar).isEmpty)
    }

    @Test func toggleFlipsTheStar() async {
        let stars = makeStars()

        await stars.toggle(storyID: storyID)
        #expect(stars.isStarred(storyID))
        await stars.toggle(storyID: storyID)
        #expect(!stars.isStarred(storyID))
    }

    @Test func theServersValueShowsWhenNothingWaits() async {
        let stars = makeStars()
        await environment.cache.saveStars([storyID: true], ownerUserID: Fixture.me)

        await stars.reload()

        #expect(stars.isStarred(storyID))
    }

    @Test func anUnsentChangeBeatsTheServersValue() async {
        let stars = makeStars()
        await environment.cache.saveStars([storyID: true], ownerUserID: Fixture.me)
        await stars.reload()

        await stars.setStarred(false, storyID: storyID)

        #expect(!stars.isStarred(storyID))
    }

    @Test func aStarWaitingInTheQueueSurvivesARelaunch() async throws {
        try await enqueueStar(true, sequence: 1)
        let afterRelaunch = makeStars()

        await afterRelaunch.reload()

        #expect(afterRelaunch.isStarred(storyID))
    }

    @Test func theLastQueuedWriteOfAStoryWinsWhenReadingTheQueue() async throws {
        try await enqueueStar(true, sequence: 1)
        try await enqueueStar(false, sequence: 2)
        let other = UUID()
        try await enqueueStar(true, sequence: 3, storyID: other)

        let queued = await StoryChainStars.queuedStars(from: environment.pending, ownerUserID: Fixture.me)

        #expect(queued == [storyID: false, other: true])
    }

    @Test func aQueueThatCannotBeReadIsNotAnEmptyOne() async {
        let unreadable = UnreadableStoryChainPendingStore()

        #expect(await StoryChainStars.queuedStars(from: unreadable, ownerUserID: Fixture.me) == nil)
    }

    @Test func aStarThePhoneCannotSaveDoesNotShowAndTellsThePerson() async {
        let broken = StoryChainDataEnvironment(pending: UnreadableStoryChainPendingStore())
        let stars = makeStars(broken)

        await stars.setStarred(true, storyID: storyID)

        #expect(!stars.isStarred(storyID))
        #expect(stars.notice == .couldNotSaveMove)
        stars.clearNotice()
        #expect(stars.notice == nil)
    }

    @Test func nothingIsStarredWithoutASignedInPerson() async {
        let stars = StoryChainStars(dependencies: environment.dependencies()) { nil }

        await stars.setStarred(true, storyID: storyID)

        #expect(!stars.isStarred(storyID))
        #expect(await environment.queued(.storyChainSetStar).isEmpty)
    }

    @Test func aLocalChangeAsksTheSyncToSend() async {
        let stars = makeStars()
        let sent = Counter()
        stars.setLocalChangeSyncHandler { await sent.increment() }

        await stars.setStarred(true, storyID: storyID)

        #expect(await waitUntilCounted(sent, atLeast: 1))
    }

    // MARK: Pages read from the server

    @Test func aPageReadBeforeTheChangeNeverUndoesIt() async {
        let stars = makeStars()
        let mark = stars.changeMark
        await stars.setStarred(true, storyID: storyID)
        let other = UUID()

        // A history page that was read before the star reached the server.
        await stars.applyServerStars([storyID: false, other: true], readSince: mark)

        #expect(stars.isStarred(storyID))
        #expect(stars.isStarred(other))
        let document = await environment.cache.document(ownerUserID: Fixture.me)
        #expect(document.stars[other] == true)
        #expect(document.stars[storyID] == nil)
    }

    @Test func aPageReadAfterTheChangeIsTaken() async {
        let stars = makeStars()
        await stars.setStarred(true, storyID: storyID)
        let mark = stars.changeMark

        // The change was sent and the server says so. Nothing waits in the queue any more.
        let queued = await environment.queued(.storyChainSetStar)
        for operation in queued {
            try? await environment.pending.markSucceeded(clientOperationID: operation.operation.id, at: Fixture.now)
        }
        await stars.reload()
        await stars.applyServerStars([storyID: true], readSince: mark)

        #expect(stars.isStarred(storyID))
        #expect(await environment.cache.document(ownerUserID: Fixture.me).stars[storyID] == true)
    }

    // MARK: The state and the first page

    @Test func aStoryStarredOnTheOtherPhoneShowsFromTheState() async {
        let state = finishedStoryChainState(finishedStoryChainStory(starred: true))
        let env = StoryChainDataEnvironment(state: state)
        let stars = makeStars(env)

        await stars.reload()

        #expect(stars.isStarred(Fixture.storyID))
    }

    @Test func thePreviousStoryOfTheStateCountsToo() async {
        let previous = finishedStoryChainStory(starred: true)
        let next = Fixture.story(.writing, id: Fixture.nextStoryID, number: 2)
        let state = Fixture.state(
            Fixture.game(.writing, turn: Fixture.me, current: next.id, stories: 2),
            current: next,
            previous: previous
        )
        let stars = makeStars(StoryChainDataEnvironment(state: state))

        await stars.reload()

        #expect(stars.isStarred(previous.id))
        #expect(!stars.isStarred(next.id))
    }

    @Test func theStateBeatsAnOlderCachedStar() async {
        let starred = finishedStoryChainState(finishedStoryChainStory(starred: true), version: 1)
        let env = StoryChainDataEnvironment(state: starred)
        let stars = makeStars(env)
        // The other phone removed the star, and the live feed brings the news.
        let unstarred = finishedStoryChainState(finishedStoryChainStory(starred: false), version: 2)
        await env.cache.saveState(unstarred, ownerUserID: Fixture.me)

        await stars.reload()

        #expect(!stars.isStarred(Fixture.storyID))
    }

    @Test func anUnsentChangeBeatsTheState() async {
        let env = StoryChainDataEnvironment(state: finishedStoryChainState(finishedStoryChainStory(starred: true)))
        let stars = makeStars(env)
        await stars.reload()

        await stars.setStarred(false, storyID: Fixture.storyID)

        #expect(!stars.isStarred(Fixture.storyID))
    }

    @Test func theFirstPageOfTheHistoryTellsTheStarsOfOlderStories() async {
        let item = storyChainHistoryItem(3, starred: true)
        await environment.cache.saveHistoryFirstPage(
            RemoteStoryChainHistoryPage(stories: [item, storyChainHistoryItem(2)], nextBeforeStoryNumber: nil),
            ownerUserID: Fixture.me
        )
        let stars = makeStars()

        await stars.reload()

        #expect(stars.isStarred(item.id))
        #expect(!stars.isStarred(storyChainHistoryItem(2).id))
    }

    @Test func aStarWriteTheServerAnsweredBeatsTheOlderFirstPage() async {
        let item = storyChainHistoryItem(3, starred: true)
        await environment.cache.saveHistoryFirstPage(
            RemoteStoryChainHistoryPage(stories: [item], nextBeforeStoryNumber: nil),
            ownerUserID: Fixture.me
        )
        let stars = makeStars()
        await environment.cache.saveStars([item.id: false], ownerUserID: Fixture.me)

        await stars.reload()

        #expect(!stars.isStarred(item.id))
    }
}

/// Counts calls from a `@Sendable` handler.
private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
private func waitUntilCounted(_ counter: Counter, atLeast target: Int) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while await counter.value < target {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
