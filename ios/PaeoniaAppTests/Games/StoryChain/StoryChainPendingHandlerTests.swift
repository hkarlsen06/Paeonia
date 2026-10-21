import Foundation
import Testing
@testable import PaeoniaApp

/// What happens to a queued Story Chain move once the server answers: it reads
/// the state before it leaves the queue, a refusal drops it and tells the
/// person, and a lost connection never does.
@MainActor
struct StoryChainPendingHandlerTests {
    private typealias Fixture = StoryChainFixture

    private let environment = StoryChainDataEnvironment()
    private let serverError = PaeoniaConvexError.server(code: nil, message: "Server Error")
    private let notYourTurn = PaeoniaConvexError.server(code: "42501", message: "not your turn")
    private let ruleBroken = PaeoniaConvexError.server(code: "23514", message: "the line must use the dare word")

    private var gateway: ScriptedStoryChainDataGateway { environment.gateway }

    private func lineHandler() -> StoryChainLinePendingOperationHandler { environment.lineHandler() }
    private func startHandler() -> StoryChainStartPendingOperationHandler { environment.startHandler() }
    private func nameHandler() -> StoryChainNamePendingOperationHandler { environment.nameHandler() }
    private func seenHandler() -> StoryChainSeenPendingOperationHandler { environment.seenHandler() }

    private func name(of storyID: UUID = Fixture.storyID) -> StoryChainQueuedName {
        StoryChainQueuedName(storyID: storyID, title: "The night bus")
    }

    private func seenMark(_ storyID: UUID = Fixture.storyID) -> StoryChainSeenPayload {
        StoryChainSeenPayload(storyID: storyID)
    }

    /// Whether sending the move fails with an error, which keeps it in the queue.
    private func sendThrows(
        _ handler: some PendingSyncOperationHandling,
        _ move: PendingSyncOperationSnapshot
    ) async -> Bool {
        do {
            _ = try await handler.send(move, context: environment.context)
            return false
        } catch {
            return true
        }
    }

    private func cachedNotices() async -> [GameStoredNotice] {
        await environment.cache.document(ownerUserID: Fixture.me).notices
    }

    private func rescuedLines() async -> [String] {
        await environment.cache.document(ownerUserID: Fixture.me).rescuedLines
    }

    // MARK: A move the server took

    @Test func aMoveReadsTheServersStateBeforeLeavingTheQueue() async throws {
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        await environment.drain()

        #expect(await environment.queued(.storyChainAddLine).isEmpty)
        #expect(await environment.cache.document(ownerUserID: Fixture.me).state == storyChainStateAfterAMove())
    }

    @Test func aMoveStaysQueuedWhenTheReadFailsAndIsTriedAgainWithinSeconds() async throws {
        gateway.fail("load")
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        let before = Date()
        let result = try await lineHandler().send(line, context: environment.context)

        guard case let .retry(after: date?) = result else {
            Issue.record("expected a retry with a date, got \(result)")
            return
        }
        #expect(gateway.lines.count == 1)
        let wait = date.timeIntervalSince(before)
        #expect(wait > 1 && wait <= 5)
    }

    @Test func aMoveTheServerAlreadyHasIsDoneAfterReadingTheState() async throws {
        gateway.setError(.server(code: "23505", message: "duplicate key value violates unique constraint"), for: "line")
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        let result = try await lineHandler().send(line, context: environment.context)

        #expect(result == .succeeded)
        #expect(await environment.cache.document(ownerUserID: Fixture.me).state == storyChainStateAfterAMove())
        #expect(await cachedNotices().isEmpty)
    }

    // MARK: Refusals

    @Test func aRuleTheServerEnforcesDropsTheMoveAndTellsThePerson() async throws {
        gateway.setError(ruleBroken, for: "line")
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        let result = try await lineHandler().send(line, context: environment.context)

        guard case .terminalFailure = result else {
            Issue.record("expected the move to be dropped, got \(result)")
            return
        }
        #expect(await cachedNotices() == [.moveRejected])
        // The words go back to the next composer.
        #expect(await rescuedLines() == [Fixture.queuedLine().text])
    }

    @Test func aMoveMadeOutOfTurnIsDroppedAndTheNoticeIsKept() async throws {
        gateway.setError(notYourTurn, for: "name")
        let queued = try environment.snapshot(.storyChainNameStory, name(), sequence: 1)

        let result = try await nameHandler().send(queued, context: environment.context)

        guard case .terminalFailure = result else {
            Issue.record("expected the title to be dropped, got \(result)")
            return
        }
        #expect(await cachedNotices() == [.moveRejected])
    }

    @Test func aRefusalThePhoneHasNoRuleForIsDroppedOnTheThirdTry() async throws {
        gateway.setError(serverError, for: "line")
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        for _ in 0..<2 {
            #expect(await sendThrows(lineHandler(), line))
        }
        #expect(await cachedNotices().isEmpty)

        let third = try await lineHandler().send(line, context: environment.context)

        guard case .terminalFailure = third else {
            Issue.record("expected the move to be dropped, got \(third)")
            return
        }
        #expect(await cachedNotices() == [.moveRejected])
    }

    @Test func aLostConnectionNeverDropsAMove() async throws {
        gateway.fail("line")
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        for _ in 0..<6 {
            #expect(await sendThrows(lineHandler(), line))
        }

        #expect(await cachedNotices().isEmpty)
    }

    @Test func aSignInOrAccessRefusalKeepsRetrying() async throws {
        gateway.setError(.server(code: "42501", message: "active entitled game access is required"), for: "line")
        let line = try environment.snapshot(.storyChainAddLine, Fixture.queuedLine(), sequence: 1)

        for _ in 0..<6 {
            #expect(await sendThrows(lineHandler(), line))
        }

        #expect(await cachedNotices().isEmpty)
    }

    @Test func aRefusedStartStopsTheMovesQueuedForItsStory() async throws {
        gateway.setError(notYourTurn, for: "start")
        let start = Fixture.queuedStart(story: Fixture.nextStoryID)
        let startSnapshot = try environment.snapshot(.storyChainStartStory, start, sequence: 1)
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(story: Fixture.nextStoryID), sequence: 2)
        try await environment.enqueue(.storyChainNameStory, name(of: Fixture.nextStoryID), sequence: 3)
        try await environment.enqueue(.storyChainMarkSeen, seenMark(Fixture.nextStoryID), sequence: 4)
        // Another story's moves go on.
        try await environment.enqueue(.storyChainAddLine, Fixture.queuedLine(story: Fixture.storyID), sequence: 6)

        let result = try await startHandler().send(startSnapshot, context: environment.context)

        guard case .terminalFailure = result else {
            Issue.record("expected the start to be dropped, got \(result)")
            return
        }
        #expect(await environment.queued(.storyChainNameStory).isEmpty)
        #expect(await environment.queued(.storyChainMarkSeen).isEmpty)
        let lines = await environment.queued(.storyChainAddLine)
        #expect(lines.count == 1)
        #expect(await cachedNotices() == [.moveRejected])
        // The line written for the refused story goes back to the next composer.
        #expect(await rescuedLines() == [Fixture.queuedLine(story: Fixture.nextStoryID).text])
    }

    // MARK: Seen marks

    @Test func aSeenMarkTheServerRefusesForGoodIsDroppedWithoutANotice() async throws {
        gateway.setError(.server(code: "23514", message: "the story is not finished"), for: "seen")
        let seen = try environment.snapshot(.storyChainMarkSeen, seenMark(Fixture.storyID), sequence: 1)

        let result = try await seenHandler().send(seen, context: environment.context)

        guard case .terminalFailure = result else {
            Issue.record("expected the mark to be dropped, got \(result)")
            return
        }
        #expect(await cachedNotices().isEmpty)
    }

    @Test func aSeenMarkThatFailsForAnotherReasonKeepsRetrying() async throws {
        gateway.setError(serverError, for: "seen")
        let seen = try environment.snapshot(.storyChainMarkSeen, seenMark(Fixture.storyID), sequence: 1)

        for _ in 0..<4 {
            #expect(await sendThrows(seenHandler(), seen))
        }
    }

    @Test func anAcceptedSeenMarkReadsTheStateBeforeLeavingTheQueue() async throws {
        try await environment.enqueue(.storyChainMarkSeen, seenMark(Fixture.storyID), sequence: 1)

        await environment.drain()

        #expect(gateway.seenStories == [Fixture.storyID])
        #expect(await environment.queued(.storyChainMarkSeen).isEmpty)
        #expect(await environment.cache.document(ownerUserID: Fixture.me).state == storyChainStateAfterAMove())
    }
}
