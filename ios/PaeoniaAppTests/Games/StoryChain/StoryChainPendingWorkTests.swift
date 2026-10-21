import Foundation
import Testing
@testable import PaeoniaApp

/// What the queue tells the screens about the Story Chain moves waiting on this
/// phone, and how the screens put moves in the queue.
@MainActor
struct StoryChainPendingWorkTests {
    private typealias Fixture = StoryChainFixture

    private let environment = StoryChainDataEnvironment()
    private let serverRefusal = String(describing: PaeoniaConvexError.server(code: nil, message: "Server Error"))

    private func load(from store: (any PendingSyncOperationPersisting)? = nil) async -> StoryChainPendingWork? {
        await StoryChainPendingWork.load(from: store ?? environment.pending, ownerUserID: Fixture.me)
    }

    // MARK: Reading the queue

    @Test func everyKindIsReadOldestFirst() async throws {
        let first = Fixture.queuedLine(id: UUID())
        let second = Fixture.queuedLine(id: UUID())
        try await environment.enqueue(.storyChainAddLine, first, sequence: 1)
        try await environment.enqueue(.storyChainStartStory, Fixture.queuedStart(), sequence: 2)
        try await environment.enqueue(.storyChainAddLine, second, sequence: 3)
        let name = StoryChainQueuedName(storyID: Fixture.storyID, title: "The night bus")
        try await environment.enqueue(.storyChainNameStory, name, sequence: 4)
        let seen = StoryChainSeenPayload(storyID: Fixture.nextStoryID)
        try await environment.enqueue(.storyChainMarkSeen, seen, sequence: 5)

        let work = try #require(await load())

        #expect(work.lines == [first, second])
        #expect(work.starts == [Fixture.queuedStart()])
        #expect(work.names == [name])
        #expect(work.seenStoryIDs == [Fixture.nextStoryID])
        #expect(work.hasMoveWaiting)
        #expect(!work.isEmpty)
    }

    @Test func aSeenMarkAloneIsNotAMoveButIsNotEmpty() async throws {
        try await environment.enqueue(.storyChainMarkSeen, StoryChainSeenPayload(storyID: Fixture.storyID), sequence: 1)

        let work = try #require(await load())

        #expect(!work.hasMoveWaiting)
        #expect(!work.isEmpty)
    }

    @Test func aFavoriteIsNotPartOfThePendingWork() async throws {
        let favorite = FavoriteWritePayload(
            target: .storyChainStory(Fixture.storyID),
            favorited: true,
            createdAt: Fixture.now
        )
        try await environment.enqueue(.setFavorite, favorite, sequence: 1)

        #expect(await load()?.isEmpty == true)
    }

    @Test func aPayloadThatCannotBeReadIsSkipped() async throws {
        try await environment.enqueue(.storyChainAddLine, ["storyID": "not a story"], sequence: 1)
        let line = Fixture.queuedLine()
        try await environment.enqueue(.storyChainAddLine, line, sequence: 2)

        #expect(await load()?.lines == [line])
    }

    @Test func aQueueThatCannotBeReadIsNotAnEmptyQueue() async {
        // Reading it as empty would make a queued line look lost.
        #expect(await load(from: UnreadableStoryChainPendingStore()) == nil)
    }

    @Test func anotherPersonsMovesAreNotRead() async throws {
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: Fixture.partner,
                operation: environment.operation(1),
                operationKind: .storyChainAddLine,
                idempotencyScope: "story-chain",
                requestData: try JSONEncoder().encode(Fixture.queuedLine())
            )
        )

        #expect(await load()?.isEmpty == true)
    }

    // MARK: Held on the phone

    private func fail(_ operationID: UUID, with error: String) async throws {
        try await environment.pending.markSending(clientOperationID: operationID, at: Fixture.now)
        try await environment.pending.markRetryableFailure(
            clientOperationID: operationID,
            errorDescription: error,
            nextRetryAt: nil,
            at: Fixture.now
        )
    }

    @Test func aMoveOnItsFirstSendIsNotHeldOnThePhone() async throws {
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        let work = try #require(await load())

        #expect(!work.isHeldOnPhone)
        #expect(!work.lastSendFailedWhileOnline)
    }

    @Test func aMoveIsHeldOnThePhoneOnceATryFailed() async throws {
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)
        let operationID = try #require(await environment.queued(.storyChainAddLine).first?.operation.id)

        // A move that waits behind an earlier one, or has no connection, is held but not failing.
        try await fail(operationID, with: "Retry later")
        let waiting = try #require(await load())
        #expect(waiting.isHeldOnPhone)
        #expect(!waiting.lastSendFailedWhileOnline)

        try await fail(operationID, with: "NSURLErrorDomain Code=-1009")
        let offline = try #require(await load())
        #expect(offline.isHeldOnPhone)
        #expect(!offline.lastSendFailedWhileOnline)
    }

    @Test func aRefusalFromTheServerMeansTheSendFailedWhileOnline() async throws {
        let name = StoryChainQueuedName(storyID: Fixture.storyID, title: "A")
        try await environment.enqueue(.storyChainNameStory, name, sequence: 1)
        let operationID = try #require(await environment.queued(.storyChainNameStory).first?.operation.id)

        try await fail(operationID, with: serverRefusal)

        let work = try #require(await load())
        #expect(work.isHeldOnPhone)
        #expect(work.lastSendFailedWhileOnline)
    }

    @Test func aSeenMarkThatCannotBeSentDoesNotHoldTheMovesBack() async throws {
        try await environment.enqueue(.storyChainMarkSeen, StoryChainSeenPayload(storyID: Fixture.storyID), sequence: 1)
        let operationID = try #require(await environment.queued(.storyChainMarkSeen).first?.operation.id)

        try await fail(operationID, with: serverRefusal)

        let work = try #require(await load())
        #expect(!work.isHeldOnPhone)
        #expect(!work.lastSendFailedWhileOnline)
    }

    // MARK: Queueing

    @Test func movesQueuedOneAfterTheOtherKeepTheirOrder() async throws {
        let queue = StoryChainMoveQueue(dependencies: environment.dependencies())
        let lines = (0..<3).map { _ in Fixture.queuedLine() }

        for line in lines {
            try await queue.addLine(line, ownerUserID: Fixture.me)
        }

        #expect(await load()?.lines == lines)
    }

    @Test func aMoveThePhoneCannotSaveThrows() async {
        let broken = StoryChainDataEnvironment(pending: UnreadableStoryChainPendingStore())
        let queue = StoryChainMoveQueue(dependencies: broken.dependencies())

        var didThrow = false
        do {
            try await queue.addLine(Fixture.queuedLine(), ownerUserID: Fixture.me)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
