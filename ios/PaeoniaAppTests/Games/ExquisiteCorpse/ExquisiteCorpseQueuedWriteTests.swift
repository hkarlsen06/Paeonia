import Foundation
import Testing
@testable import PaeoniaApp

/// The reveal seen mark: the order it goes in, what a refusal does, and how the
/// screens read the queue back.
@MainActor
struct ExquisiteCorpseQueuedWriteTests {
    private typealias Fixture = ExquisiteCorpseFixture

    private let environment = ExquisiteCorpseDataEnvironment()

    private func revealSeen(figure: Int) -> ExquisiteCorpseRevealSeenPayload {
        ExquisiteCorpseRevealSeenPayload(figureID: Fixture.figureID(figure), createdAt: Fixture.now)
    }

    /// Operations made one after the other, the way the factory numbers them.
    private func makeOperation(_ sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(
            id: UUID(),
            clientID: Fixture.me,
            clientSequence: sequence,
            localCreatedAt: Fixture.now.addingTimeInterval(Double(sequence))
        )
    }

    private func loadWork(_ owner: UUID = Fixture.me) async throws -> ExquisiteCorpsePendingWork {
        try #require(await ExquisiteCorpsePendingWork.load(from: environment.pending, ownerUserID: owner))
    }

    /// Queues a part, tries it once, and leaves it waiting for a retry with `lastError` set.
    private func queueFailedPart(lastError: String) async throws {
        let operation = makeOperation(1)
        let part = Fixture.queuedPart(figure: 2, partIndex: 0)
        try await environment.enqueue(.exquisiteCorpseSubmitPart, part, operation: operation)
        try await environment.pending.markSending(clientOperationID: operation.id, at: Fixture.now)
        try await environment.pending.markRetryableFailure(
            clientOperationID: operation.id,
            errorDescription: lastError,
            nextRetryAt: nil,
            at: Fixture.now
        )
    }

    // MARK: Reveal seen

    @Test func theMarkWaitsForThePartQueuedForTheSameFigure() async throws {
        try await environment.enqueue(.exquisiteCorpseSubmitPart, Fixture.queuedPart(figure: 1, partIndex: 2))

        let result = try await environment.revealSeenHandler().send(
            try corpseSnapshot(.exquisiteCorpseRevealSeen, revealSeen(figure: 1), operation: makeOperation(2)),
            context: environment.context()
        )

        #expect(result == .retry(after: nil))
        #expect(environment.gateway.calls.isEmpty)
    }

    @Test func aPartOfAnotherFigureDoesNotHoldTheMarkBack() async throws {
        try await environment.enqueue(.exquisiteCorpseSubmitPart, Fixture.queuedPart(figure: 2, partIndex: 0))

        let result = try await environment.revealSeenHandler().send(
            try corpseSnapshot(.exquisiteCorpseRevealSeen, revealSeen(figure: 1), operation: makeOperation(2)),
            context: environment.context()
        )

        #expect(result == .succeeded)
        #expect(environment.gateway.revealSeen == [Fixture.figureID(1)])
    }

    @Test func theServersStateIsReadAfterTheMark() async throws {
        let result = try await environment.revealSeenHandler().send(
            try corpseSnapshot(.exquisiteCorpseRevealSeen, revealSeen(figure: 1)),
            context: environment.context()
        )

        #expect(result == .succeeded)
        #expect(environment.gateway.calls == ["revealSeen", "load"])
        #expect(await environment.cache.document(ownerUserID: Fixture.me).state != nil)
    }

    @Test func aMarkStaysQueuedWhenTheStateReadAfterItFails() async throws {
        environment.gateway.setStateToLoad(nil)

        let result = try await environment.revealSeenHandler().send(
            try corpseSnapshot(.exquisiteCorpseRevealSeen, revealSeen(figure: 1)),
            context: environment.context()
        )

        guard case let .retry(after: date) = result else {
            Issue.record("Expected a retry, got \(result)")
            return
        }
        #expect(date != nil)
    }

    @Test func aMarkARetryCannotFixIsDroppedWithoutANotice() async throws {
        environment.gateway.setRevealSeenError(Fixture.refusal("23514", "the creature is not finished yet"))

        let result = try await environment.revealSeenHandler().send(
            try corpseSnapshot(.exquisiteCorpseRevealSeen, revealSeen(figure: 1)),
            context: environment.context()
        )

        expectCorpseTerminalFailure(result)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me).isEmpty)
    }

    @Test func anyOtherErrorKeepsTheMarkInTheQueue() async throws {
        let handler = environment.revealSeenHandler()
        let snapshot = try corpseSnapshot(.exquisiteCorpseRevealSeen, revealSeen(figure: 1))

        let errors: [any Error] = [
            Fixture.refusal("42501", "active entitled game access is required"),
            Fixture.refusal("XX000", "something we do not know"),
            URLError(.notConnectedToInternet),
        ]
        for error in errors {
            environment.gateway.setRevealSeenError(error)
            let thrown = await corpseThrownError { try await handler.send(snapshot, context: environment.context()) }
            #expect(thrown != nil)
        }
    }
}

/// How the screens read the queue back.
extension ExquisiteCorpseQueuedWriteTests {
    // MARK: Reading the queue

    @Test func theQueueReadsBackWhatIsWaiting() async throws {
        let part = Fixture.queuedPart(figure: 2, partIndex: 0)
        try await environment.enqueue(.exquisiteCorpseSubmitPart, part, operation: makeOperation(1))
        let seen = revealSeen(figure: 1)
        try await environment.enqueue(.exquisiteCorpseRevealSeen, seen, operation: makeOperation(2))

        let work = try await loadWork()

        #expect(work.parts == [part])
        #expect(work.hasMoveWaiting)
        #expect(work.hasRevealSeen(figureID: Fixture.figureID(1)))
        #expect(!work.hasRevealSeen(figureID: Fixture.figureID(2)))
        #expect(!work.lastSendFailedWhileOnline && !work.hasFailedMoveAttempt)
    }

    @Test func onlyTheOwnersWritesAreRead() async throws {
        try await environment.enqueue(.exquisiteCorpseRevealSeen, revealSeen(figure: 1))

        let work = try await loadWork(Fixture.partner)

        #expect(work.isEmpty)
    }

    @Test func aWriteThatStoppedForGoodIsNoLongerWaiting() async throws {
        let part = Fixture.queuedPart(figure: 2, partIndex: 0)
        let operation = makeOperation(1)
        try await environment.enqueue(.exquisiteCorpseSubmitPart, part, operation: operation)
        try await environment.pending.markTerminalFailure(
            clientOperationID: operation.id,
            errorDescription: "refused",
            at: Fixture.now
        )

        let work = try await loadWork()

        #expect(work.isEmpty)
    }

    @Test func aPayloadThatCannotBeReadIsSkipped() async throws {
        try await environment.enqueue(.exquisiteCorpseSubmitPart, "not a part", operation: makeOperation(1))
        try await environment.enqueue(.exquisiteCorpseRevealSeen, revealSeen(figure: 1), operation: makeOperation(2))

        let work = try await loadWork()

        #expect(work.parts.isEmpty)
        #expect(work.hasRevealSeen(figureID: Fixture.figureID(1)))
    }

    @Test func aPartThatWaitedBehindSomethingIsNotAFailedAttempt() async throws {
        try await queueFailedPart(lastError: "Retry later")

        let work = try await loadWork()

        #expect(work.hasFailedMoveAttempt)
        #expect(!work.lastSendFailedWhileOnline)
    }

    @Test func aPartTheServerAnsweredBadlyIsAFailedAttemptWhileOnline() async throws {
        try await queueFailedPart(lastError: String(describing: Fixture.refusal("XX000", "something we do not know")))

        let work = try await loadWork()

        #expect(work.hasFailedMoveAttempt)
        #expect(work.lastSendFailedWhileOnline)
    }

    @Test func aFailedRevealSeenIsNotAFailedMove() async throws {
        let operation = makeOperation(1)
        try await environment.enqueue(.exquisiteCorpseRevealSeen, revealSeen(figure: 1), operation: operation)
        try await environment.pending.markSending(clientOperationID: operation.id, at: Fixture.now)
        try await environment.pending.markRetryableFailure(
            clientOperationID: operation.id,
            errorDescription: String(describing: Fixture.refusal("XX000", "something we do not know")),
            nextRetryAt: nil,
            at: Fixture.now
        )

        let work = try await loadWork()

        #expect(!work.hasFailedMoveAttempt)
        #expect(!work.lastSendFailedWhileOnline)
    }
}
