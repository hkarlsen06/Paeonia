import Foundation
import Testing
@testable import PaeoniaApp

/// What the drain does with a write that keeps failing, and with a connection that is down.
struct PendingSyncOperationDrainGiveUpTests {
    private let owner = UUID()

    @Test func anOldWriteGivesUpAfterEnoughFailuresAndTellsItsHandler() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        let old = try await enqueue(1, createdAt: Date().addingTimeInterval(-3 * 24 * 3_600), in: store)
        let handler = ScriptedHandler(failure: ScriptedFailure.serverError)
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        for _ in 0..<4 {
            try await stream.push(context: context(store))
        }

        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.isEmpty)
        #expect(await handler.gaveUpIDs == [old.id])
    }

    @Test func aWriteWhoseHandlerCannotShowTheFailureNeverGivesUp() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        _ = try await enqueue(1, createdAt: Date().addingTimeInterval(-3 * 24 * 3_600), in: store)
        let handler = ScriptedHandler(failure: ScriptedFailure.serverError, showsGivenUpWrites: false)
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        for _ in 0..<6 {
            try await stream.push(context: context(store))
        }

        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.first?.status == .failedRetryable)
        #expect(await handler.gaveUpIDs.isEmpty)
    }

    @Test func anOldWriteKeepsItsFirstTriesBeforeGivingUp() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        _ = try await enqueue(1, createdAt: Date().addingTimeInterval(-3 * 24 * 3_600), in: store)
        let handler = ScriptedHandler(failure: ScriptedFailure.serverError)
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        for _ in 0..<3 {
            try await stream.push(context: context(store))
        }

        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.count == 1)
        #expect(await handler.gaveUpIDs.isEmpty)
    }

    @Test func aWriteWaitingForAConnectionNeverGivesUp() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        _ = try await enqueue(1, createdAt: Date().addingTimeInterval(-30 * 24 * 3_600), in: store)
        let handler = ScriptedHandler(failure: URLError(.notConnectedToInternet))
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        for _ in 0..<6 {
            try await stream.push(context: context(store))
        }

        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.first?.status == .failedRetryable)
        #expect(await handler.gaveUpIDs.isEmpty)
    }

    @Test func aPayloadThatCannotBeReadFailsForGoodInsteadOfRetrying() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        _ = try await enqueue(1, createdAt: Date(), in: store)
        let handler = ScriptedHandler(failure: PendingSyncOperationPayloadError())
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        try await stream.push(context: context(store))

        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.isEmpty)
        #expect(await handler.sentIDs.count == 1)
    }

    @Test func queuedPayloadDecodingTurnsAnyDecodeFailureIntoAPayloadError() {
        #expect(throws: PendingSyncOperationPayloadError()) {
            try JSONDecoder().decodeQueuedPayload([String].self, from: Data("{".utf8))
        }
        #expect(throws: PendingSyncOperationPayloadError()) {
            try JSONDecoder().decodeQueuedPayload([String].self, from: Data("{\"a\":1}".utf8))
        }
    }

    @Test func aLostConnectionStopsTheRunInsteadOfTryingEveryWrite() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        let first = try await enqueue(1, createdAt: Date(), in: store)
        _ = try await enqueue(2, createdAt: Date(), in: store)
        _ = try await enqueue(3, createdAt: Date(), in: store)
        let handler = ScriptedHandler(failure: URLError(.notConnectedToInternet))
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        try await stream.push(context: context(store))

        #expect(await handler.sentIDs == [first.id])
        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.count == 3)
        #expect(inFlight.first?.status == .failedRetryable)
    }

    @Test func aServerErrorDoesNotStopTheRun() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        _ = try await enqueue(1, createdAt: Date(), in: store)
        _ = try await enqueue(2, createdAt: Date(), in: store)
        let handler = ScriptedHandler(failure: ScriptedFailure.serverError)
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        try await stream.push(context: context(store))

        #expect(await handler.sentIDs.count == 2)
    }

    @Test func aSlowWriteFailsAfterItsOwnLimitAndTheWritesBehindItStillGo() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        let slow = try await enqueue(1, createdAt: Date(), in: store)
        let fast = try await enqueue(2, createdAt: Date(), in: store)
        let handler = ScriptedHandler(sleepingOn: slow.id)
        let stream = PendingSyncOperationDrainStream(handlers: [handler], operationTimeout: .milliseconds(50))

        try await stream.push(context: context(store))

        #expect(await handler.sentIDs == [slow.id, fast.id])
        let inFlight = try await store.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)
        #expect(inFlight.map(\.operation.id) == [slow.id])
        #expect(inFlight.first?.status == .failedRetryable)
    }

    @Test func aFailedWriteIsNotSentAgainBeforeItsRetryDate() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        let waiting = try await enqueue(1, createdAt: Date(), in: store)
        let handler = ScriptedHandler(failure: ScriptedFailure.serverError)
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        try await stream.push(context: context(store))
        try await stream.push(context: context(store))

        // The first run set a retry date a minute out, so the second run left it alone.
        #expect(await handler.sentIDs == [waiting.id])
    }

    private func context(_ store: any PendingSyncOperationPersisting) -> SyncContext {
        SyncContext(
            session: SyncSession(userID: owner),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: store
        )
    }

    private func enqueue(
        _ sequence: Int,
        createdAt: Date,
        in store: any PendingSyncOperationPersisting
    ) async throws -> SyncClientOperation {
        let operation = SyncClientOperation(
            clientID: UUID(),
            clientSequence: Int64(sequence),
            localCreatedAt: createdAt.addingTimeInterval(TimeInterval(sequence))
        )
        try await store.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "test:\(operation.id)"
            )
        )
        return operation
    }
}

private enum ScriptedFailure: Error {
    case serverError
}

/// Fails every send with `failure`, except a write it is told to leave hanging.
private actor ScriptedHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitDailyAnswer
    nonisolated let showsGivenUpWrites: Bool
    private let failure: (any Error)?
    private let sleepingID: UUID?
    private(set) var sentIDs: [UUID] = []
    private(set) var gaveUpIDs: [UUID] = []

    init(failure: any Error, showsGivenUpWrites: Bool = true) {
        self.failure = failure
        self.showsGivenUpWrites = showsGivenUpWrites
        sleepingID = nil
    }

    init(sleepingOn sleepingID: UUID) {
        failure = nil
        showsGivenUpWrites = true
        self.sleepingID = sleepingID
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        sentIDs.append(operation.operation.id)
        if operation.operation.id == sleepingID {
            try await Task.sleep(for: .seconds(60))
        }
        if let failure {
            throw failure
        }
        return .succeeded
    }

    func gaveUp(on operation: PendingSyncOperationSnapshot, context _: SyncContext) {
        gaveUpIDs.append(operation.operation.id)
    }
}
