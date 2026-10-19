import Foundation
import Testing
@testable import PaeoniaApp

/// How the board games read the queue of unsent actions, and how an action
/// becomes a queue entry.
struct BoardGamePendingWorkTests {
    private typealias Fixture = BoardGameDataFixture

    private let me = Fixture.me
    private let pending = InMemoryPendingSyncOperationRepository()
    private let game = Fixture.game()

    /// Puts an action in the pending operations and returns its operation.
    @discardableResult
    private func enqueue(_ action: BoardGamePendingAction, sequence: Int64) async throws -> SyncClientOperation {
        let operation = Fixture.operation(sequence: sequence)
        try await pending.enqueue(BoardGamePendingWork.request(for: action, ownerUserID: me, operation: operation))
        return operation
    }

    @Test func theQueueReadsBackMovesAndRematchesInTheOrderTheyWereMade() async throws {
        let finished = Fixture.game(moves: Fixture.connectFourWin, finished: true, winner: me)
        try await enqueue(.rematch(Fixture.rematch(of: finished)), sequence: 3)
        try await enqueue(.move(Fixture.move(5, on: game)), sequence: 2)
        try await enqueue(.move(Fixture.move(4, on: game)), sequence: 1)

        let actions = try #require(await BoardGamePendingWork.load(from: pending, ownerUserID: me))

        #expect(actions == [
            .move(Fixture.move(4, on: game)),
            .move(Fixture.move(5, on: game)),
            .rematch(Fixture.rematch(of: finished))
        ])
    }

    @Test func theSequenceDecidesTheOrderEvenWhenTheClockWentBack() async throws {
        // The second move was made after the phone's clock was set back a minute.
        let later = SyncClientOperation(
            clientID: UUID(),
            clientSequence: 9,
            localCreatedAt: Fixture.now.addingTimeInterval(-60)
        )
        try await enqueue(.move(Fixture.move(5, on: game)), sequence: 1)
        try await pending.enqueue(
            BoardGamePendingWork.request(for: .move(Fixture.move(4, on: game)), ownerUserID: me, operation: later)
        )

        let actions = try #require(await BoardGamePendingWork.load(from: pending, ownerUserID: me))

        #expect(actions.map(\.kind) == [.connectFour, .connectFour])
        #expect(actions == [.move(Fixture.move(5, on: game)), .move(Fixture.move(4, on: game))])
    }

    @Test func anEmptyQueueReadsAsEmptyAndAnotherPersonsActionsAreNotMine() async throws {
        try await pending.enqueue(
            BoardGamePendingWork.request(
                for: .move(Fixture.move(5, on: game)),
                ownerUserID: Fixture.partner,
                operation: Fixture.operation(sequence: 1)
            )
        )

        let actions = await BoardGamePendingWork.load(from: pending, ownerUserID: me)

        #expect(actions == [])
    }

    @Test func aPayloadThatDoesNotDecodeIsSkipped() async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: me,
                operation: Fixture.operation(sequence: 1),
                operationKind: .boardGameMove,
                idempotencyScope: "board-game:connect_four",
                requestData: Data("not json".utf8)
            )
        )
        try await enqueue(.move(Fixture.move(5, on: game)), sequence: 2)

        let actions = await BoardGamePendingWork.load(from: pending, ownerUserID: me)

        #expect(actions == [.move(Fixture.move(5, on: game))])
    }

    private func failedWhileOnline(_ kind: GameKind = .connectFour) async -> Bool {
        await BoardGamePendingWork.failedWhileOnline(kind: kind, from: pending, ownerUserID: me)
    }

    private func hasFailedAttempt(_ kind: GameKind = .connectFour) async -> Bool {
        await BoardGamePendingWork.hasFailedAttempt(kind: kind, from: pending, ownerUserID: me)
    }

    @Test func aFirstSendIsNotAFailure() async throws {
        try await enqueue(.move(Fixture.move(4, on: game)), sequence: 1)

        #expect(await !hasFailedAttempt())
        #expect(await !failedWhileOnline())
    }

    @Test func aWaitBehindAnEarlierActionIsAnAttemptButNotAFailureWhileOnline() async throws {
        let waiting = try await enqueue(.move(Fixture.move(4, on: game)), sequence: 1)

        // The drain records a wait behind an earlier action as "Retry later".
        try await pending.markSending(clientOperationID: waiting.id, at: Fixture.now)
        try await pending.markRetryableFailure(
            clientOperationID: waiting.id,
            errorDescription: "Retry later",
            nextRetryAt: nil,
            at: Fixture.now
        )

        #expect(await hasFailedAttempt())
        #expect(await !failedWhileOnline())
    }

    @Test func aTryThatReachedTheServerAndFailedIsAFailureWhileOnline() async throws {
        let refused = try await enqueue(.move(Fixture.move(4, on: game)), sequence: 1)

        try await pending.markSending(clientOperationID: refused.id, at: Fixture.now)
        try await pending.markRetryableFailure(
            clientOperationID: refused.id,
            errorDescription: String(describing: PaeoniaConvexError.http(status: 503, body: "")),
            nextRetryAt: nil,
            at: Fixture.now
        )

        #expect(await failedWhileOnline())
        #expect(await hasFailedAttempt())
    }

    @Test func aLostConnectionIsNotAFailureWhileOnline() async throws {
        let offline = try await enqueue(.move(Fixture.move(4, on: game)), sequence: 1)

        try await pending.markSending(clientOperationID: offline.id, at: Fixture.now)
        try await pending.markRetryableFailure(
            clientOperationID: offline.id,
            errorDescription: "Error Domain=NSURLErrorDomain Code=-1009",
            nextRetryAt: nil,
            at: Fixture.now
        )

        #expect(await hasFailedAttempt())
        #expect(await !failedWhileOnline())
    }

    @Test func aFailureOfOneGameDoesNotShowOnAnother() async throws {
        let refused = try await enqueue(.move(Fixture.move(4, on: game)), sequence: 1)
        try await pending.markSending(clientOperationID: refused.id, at: Fixture.now)
        try await pending.markRetryableFailure(
            clientOperationID: refused.id,
            errorDescription: String(describing: PaeoniaConvexError.http(status: 503, body: "")),
            nextRetryAt: nil,
            at: Fixture.now
        )

        #expect(await !failedWhileOnline(.dotsAndBoxes))
        #expect(await !hasFailedAttempt(.dotsAndBoxes))
    }
}
