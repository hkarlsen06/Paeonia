import Foundation
import Testing
@testable import PaeoniaApp

/// The order queued Story Chain moves go to the server in: a line after its
/// story's start, a start after the title before it, and a star after the title
/// of its story.
@MainActor
struct StoryChainPendingOrderTests {
    private typealias Fixture = StoryChainFixture

    private let environment = StoryChainDataEnvironment()

    private var gateway: ScriptedStoryChainDataGateway { environment.gateway }

    private func lineHandler() -> StoryChainLinePendingOperationHandler { environment.lineHandler() }
    private func startHandler() -> StoryChainStartPendingOperationHandler { environment.startHandler() }
    private func seenHandler() -> StoryChainSeenPendingOperationHandler { environment.seenHandler() }

    private func name(of storyID: UUID = Fixture.storyID) -> StoryChainQueuedName {
        StoryChainQueuedName(storyID: storyID, title: "The night bus")
    }

    private func seenMark(_ storyID: UUID = Fixture.storyID) -> StoryChainSeenPayload {
        StoryChainSeenPayload(storyID: storyID)
    }

    private func favorite(_ favorited: Bool, storyID: UUID = Fixture.storyID) -> FavoriteWritePayload {
        FavoriteWritePayload(target: .storyChainStory(storyID), favorited: favorited, createdAt: Fixture.now)
    }

    @Test func aLineWaitsForTheStartOfItsStory() async throws {
        let start = Fixture.queuedStart(story: Fixture.storyID)
        try await environment.enqueue(.storyChainStartStory, start, sequence: 1)
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 2)

        let result = try await lineHandler().send(line, context: environment.context)

        #expect(result == .retry(after: nil))
        #expect(gateway.lines.isEmpty)
    }

    @Test func aLineIsSentOnceTheStartHasLanded() async throws {
        let queued = Fixture.queuedLine()
        let line = try environment.snapshot(.storyChainAddLine, queued, sequence: 2)

        let result = try await lineHandler().send(line, context: environment.context)

        #expect(result == .succeeded)
        #expect(gateway.lines == [queued])
    }

    @Test func aStartOfAnotherStoryDoesNotHoldALineBack() async throws {
        let otherStart = Fixture.queuedStart(story: Fixture.nextStoryID)
        try await environment.enqueue(.storyChainStartStory, otherStart, sequence: 1)
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(story: Fixture.storyID), sequence: 2)

        let result = try await lineHandler().send(line, context: environment.context)

        #expect(result == .succeeded)
    }

    @Test func aLineWaitsForTheEarlierLineOfItsStory() async throws {
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)
        let later = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 2)

        let result = try await lineHandler().send(later, context: environment.context)

        #expect(result == .retry(after: nil))
        #expect(gateway.lines.isEmpty)
    }

    @Test func theEarlierLineDoesNotWaitForTheLaterOne() async throws {
        let first = Fixture.queuedLine()
        try await environment.enqueue(.storyChainAddLine, first, sequence: 1)
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(), sequence: 2)
        let earlier = try #require(await environment.queued(.storyChainAddLine).first)

        let result = try await lineHandler().send(earlier, context: environment.context)

        #expect(result == .succeeded)
        #expect(gateway.lines == [first])
    }

    @Test func aLineOfAnotherStoryDoesNotHoldALineBack() async throws {
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(story: Fixture.nextStoryID), sequence: 1)
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(story: Fixture.storyID), sequence: 2)

        #expect(try await lineHandler().send(line, context: environment.context) == .succeeded)
    }

    @Test func aStartWaitsForTheTitleThatCameBeforeIt() async throws {
        try await environment.enqueue(.storyChainNameStory, name(), sequence: 1)
        let start = try environment.snapshot(.storyChainStartStory, Fixture.queuedStart(), sequence: 2)

        let result = try await startHandler().send(start, context: environment.context)

        #expect(result == .retry(after: nil))
        #expect(gateway.starts.isEmpty)
    }

    @Test func aTitleQueuedAfterTheStartDoesNotHoldItBack() async throws {
        try await environment.enqueue(.storyChainNameStory, name(), sequence: 5)
        let start = try environment.snapshot(.storyChainStartStory, Fixture.queuedStart(), sequence: 2)

        let result = try await startHandler().send(start, context: environment.context)

        #expect(result == .succeeded)
        #expect(gateway.starts == [Fixture.queuedStart()])
    }

    @Test func aSeenMarkWaitsForTheTitleOfItsStoryOnly() async throws {
        try await environment.enqueue(.storyChainNameStory, name(of: Fixture.storyID), sequence: 1)
        let ofSameStory = try environment.snapshot(.storyChainMarkSeen, seenMark(Fixture.storyID), sequence: 2)
        let ofOtherStory = try environment.snapshot(
            .storyChainMarkSeen,
            seenMark(Fixture.nextStoryID),
            sequence: 3
        )

        #expect(try await seenHandler().send(ofSameStory, context: environment.context) == .retry(after: nil))
        #expect(gateway.seenStories.isEmpty)
        #expect(try await seenHandler().send(ofOtherStory, context: environment.context) == .succeeded)
        #expect(gateway.seenStories == [Fixture.nextStoryID])
    }

    @Test func aFavoriteWaitsForTheTitleOfItsStory() async throws {
        let target = FavoriteTarget.storyChainStory(Fixture.storyID)
        let queued = try environment.snapshot(.setFavorite, favorite(true), sequence: 2)
        let gate = StoryChainFavoriteGate()
        #expect(try await gate.mustWait(for: target, operation: queued, context: environment.context) == false)

        try await environment.enqueue(.storyChainNameStory, name(), sequence: 1)

        #expect(try await gate.mustWait(for: target, operation: queued, context: environment.context))
    }

    @Test func aFavoriteDoesNotWaitForTheTitleOfAnotherStory() async throws {
        try await environment.enqueue(.storyChainNameStory, name(of: Fixture.nextStoryID), sequence: 1)
        let queued = try environment.snapshot(.setFavorite, favorite(true), sequence: 2)

        let waits = try await StoryChainFavoriteGate()
            .mustWait(for: .storyChainStory(Fixture.storyID), operation: queued, context: environment.context)

        #expect(!waits)
    }

    // MARK: A whole outbox

    @Test func aStoryStartedAndWrittenOfflineGoesOutInOrderOnceTheConnectionIsBack() async throws {
        let first = Fixture.queuedLine()
        let second = Fixture.queuedLine()
        gateway.fail("start")
        try await environment.enqueue(.storyChainStartStory, Fixture.queuedStart(story: Fixture.storyID), sequence: 1)
        try await environment.enqueue(.storyChainAddLine, first, sequence: 2)
        try await environment.enqueue(.storyChainAddLine, second, sequence: 3)

        await environment.drain()

        // Neither line goes ahead of the start that cannot be sent.
        #expect(gateway.lines.isEmpty)
        #expect(await environment.queued(.storyChainAddLine).count == 2)

        gateway.unfail("start")
        await environment.drain()

        #expect(gateway.starts.map(\.storyID) == [Fixture.storyID])
        #expect(gateway.lines == [first, second])
        #expect(await environment.queued(.storyChainStartStory).isEmpty)
        #expect(await environment.queued(.storyChainAddLine).isEmpty)
    }

    @Test func aTitleAndTheStartOfTheNextStoryGoOutInOrder() async throws {
        try await environment.enqueue(.storyChainNameStory, name(), sequence: 1)
        try await environment.enqueue(.storyChainStartStory, Fixture.queuedStart(), sequence: 2)
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(story: Fixture.nextStoryID), sequence: 3)

        await environment.drain()

        #expect(gateway.calls.filter { ["name", "start", "line"].contains($0) } == ["name", "start", "line"])
        #expect(await environment.queued(.storyChainNameStory).isEmpty)
    }
}
