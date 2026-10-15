import Foundation
import SwiftData
import Testing
@testable import PaeoniaApp

struct PendingSyncOperationDrainStreamTests {
    @Test func drainStreamSendsSupportedOperations() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(operation.id)"
            )
        )
        let handler = RecordingPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(handlers: [handler])
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )

        try await stream.push(context: context)
        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(await handler.sentOperationIDs == [operation.id])
        #expect(readyOperations.isEmpty)
    }

    @Test func drainStreamSkipsAnOperationCancelledAfterTheBatchWasRead() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let clientID = testUUID("33333333-3333-3333-3333-333333333333")
        let first = SyncClientOperation(
            id: testUUID("22222222-2222-2222-2222-222222222221"),
            clientID: clientID,
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let second = SyncClientOperation(
            id: testUUID("22222222-2222-2222-2222-222222222222"),
            clientID: clientID,
            clientSequence: 2,
            localCreatedAt: Date(timeIntervalSince1970: 101)
        )
        let pendingStore = InMemoryPendingSyncOperationRepository()
        for operation in [first, second] {
            try await pendingStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: ownerUserID,
                    operation: operation,
                    operationKind: .updateLatestPartnerLocation,
                    idempotencyScope: "location:\(operation.id)"
                )
            )
        }
        // Sending the first one cancels the second, like an opt-out mid-drain.
        let handler = CancellingPendingOperationHandler(cancelling: second.id, in: pendingStore)
        let stream = PendingSyncOperationDrainStream(handlers: [handler])
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )

        try await stream.push(context: context)

        #expect(await handler.sentOperationIDs == [first.id])
    }

    @Test func drainStreamFailsOperationsWithoutHandlers() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(operation.id)"
            )
        )
        let stream = PendingSyncOperationDrainStream(handlers: [])
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )

        do {
            try await stream.push(context: context)
            Issue.record("Expected missing handler to fail the drain stream")
        } catch let error as PendingSyncOperationDrainError {
            #expect(error == .unsupportedOperationKind("submit_daily_answer"))
        }

        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(readyOperations.map(\.operation.id) == [operation.id])
    }

    @Test func thrownErrorsStayRetryableByDefault() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(operation.id)"
            )
        )

        let handler = ThrowingPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )

        for _ in 0..<10 {
            try await stream.push(context: context)
        }

        let operations = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .submitDailyAnswer
        )
        #expect(operations.first?.status == .failedRetryable)
        #expect(operations.first?.attemptCount == 10)
    }

    @Test func configuredMaximumAttemptsCanStillMarkRetryFailuresTerminal() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(operation.id)"
            )
        )

        let handler = ThrowingPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(maximumAttempts: 2, baseDelaySeconds: 0)
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )

        try await stream.push(context: context)
        try await stream.push(context: context)

        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date()
        )
        #expect(readyOperations.isEmpty)
    }
}

/// A run sends every waiting write once, and one write never holds up the others.
struct PendingSyncOperationDrainRunTests {
    @Test func drainStreamStillSendsWritesQueuedBehindAnOperationWithoutAHandler() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let unsupported = try await enqueue(
            1,
            kind: .createMemory,
            owner: ownerUserID,
            in: pendingStore
        )
        let supported = try await enqueue(2, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
        let handler = RecordingPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        await #expect(throws: PendingSyncOperationDrainError.unsupportedOperationKind("create_memory")) {
            try await stream.push(context: Self.context(owner: ownerUserID, store: pendingStore))
        }

        #expect(await handler.sentOperationIDs == [supported.id])
        let stillWaiting = try await pendingStore.readyOperations(ownerUserID: ownerUserID, limit: 10, now: Date())
        #expect(stillWaiting.map(\.operation.id) == [unsupported.id])
    }

    @Test func drainStreamSendsEveryWaitingWriteNotJustTheFirstBatch() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let pendingStore = InMemoryPendingSyncOperationRepository()
        var queued: [UUID] = []
        for sequence in 1...5 {
            let operation = try await enqueue(sequence, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
            queued.append(operation.id)
        }
        let handler = RecordingPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(handlers: [handler], batchSize: 2)

        try await stream.push(context: Self.context(owner: ownerUserID, store: pendingStore))

        #expect(await handler.sentOperationIDs == queued)
    }

    @Test func drainStreamSendsAWriteThatIsWaitingOutItsRetryDelay() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let operation = try await enqueue(1, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
        // An earlier offline attempt pushed the next try an hour out.
        try await pendingStore.markSending(clientOperationID: operation.id, at: Date())
        try await pendingStore.markRetryableFailure(
            clientOperationID: operation.id,
            errorDescription: "offline",
            nextRetryAt: Date().addingTimeInterval(3_600),
            at: Date()
        )
        let handler = RecordingPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        try await stream.push(context: Self.context(owner: ownerUserID, store: pendingStore, reason: .foreground))

        #expect(await handler.sentOperationIDs == [operation.id])
    }

    @Test func drainStreamTriesAFailingWriteOnlyOncePerRun() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let pendingStore = InMemoryPendingSyncOperationRepository()
        _ = try await enqueue(1, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
        let stream = PendingSyncOperationDrainStream(
            handlers: [ThrowingPendingOperationHandler(operationKind: .submitDailyAnswer)],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )

        try await stream.push(context: Self.context(owner: ownerUserID, store: pendingStore))

        let operations = try await pendingStore.inFlightOperations(ownerUserID: ownerUserID, kind: .submitDailyAnswer)
        #expect(operations.first?.attemptCount == 1)
    }

    @Test func drainStreamRemovesWritesTheServerAlreadyAccepted() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        _ = try await enqueue(1, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
        let stream = PendingSyncOperationDrainStream(
            handlers: [RecordingPendingOperationHandler(operationKind: .submitDailyAnswer)]
        )
        let context = Self.context(owner: ownerUserID, store: pendingStore)

        try await stream.push(context: context)
        try await stream.push(context: context)

        let rows = try ModelContext(localStore.container).fetchCount(FetchDescriptor<LocalPendingSyncOperation>())
        #expect(rows == 0)
    }

    @Test func drainStreamDoesNotSendAWritePurgedAfterTheBatchWasRead() async throws {
        let ownerUserID = testUUID("11111111-1111-1111-1111-111111111111")
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        let first = try await enqueue(1, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
        _ = try await enqueue(2, kind: .submitDailyAnswer, owner: ownerUserID, in: pendingStore)
        // Sending the first write ends the relationship, which purges every queued write.
        let handler = PurgingPendingOperationHandler(
            purger: SwiftDataLocalPrivacyRecordStore(container: localStore.container)
        )
        let stream = PendingSyncOperationDrainStream(handlers: [handler])

        try await stream.push(context: Self.context(owner: ownerUserID, store: pendingStore))

        #expect(await handler.sentOperationIDs == [first.id])
    }

    private static func context(
        owner: UUID,
        store: any PendingSyncOperationPersisting,
        reason: SyncRequestReason = .localChange
    ) -> SyncContext {
        SyncContext(
            session: SyncSession(userID: owner),
            reason: reason,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: store
        )
    }

    private func enqueue(
        _ sequence: Int,
        kind: SyncPendingOperationKind,
        owner: UUID,
        in store: any PendingSyncOperationPersisting
    ) async throws -> SyncClientOperation {
        let operation = SyncClientOperation(
            clientID: testUUID("33333333-3333-3333-3333-333333333333"),
            clientSequence: Int64(sequence),
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(100 + sequence))
        )
        try await store.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner,
                operation: operation,
                operationKind: kind,
                idempotencyScope: "test:\(operation.id)"
            )
        )
        return operation
    }
}

private actor RecordingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind
    private var sentIDs: [UUID] = []

    init(operationKind: SyncPendingOperationKind) {
        self.operationKind = operationKind
    }

    var sentOperationIDs: [UUID] {
        sentIDs
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) throws -> PendingSyncOperationSendResult {
        sentIDs.append(operation.operation.id)
        return .succeeded
    }
}

private enum PendingSyncOperationTestError: Error {
    case requestedFailure
}

private actor ThrowingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind

    init(operationKind: SyncPendingOperationKind) {
        self.operationKind = operationKind
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) throws -> PendingSyncOperationSendResult {
        throw PendingSyncOperationTestError.requestedFailure
    }
}

private actor CancellingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .updateLatestPartnerLocation
    private let cancelledID: UUID
    private let store: InMemoryPendingSyncOperationRepository
    private(set) var sentOperationIDs: [UUID] = []

    init(cancelling cancelledID: UUID, in store: InMemoryPendingSyncOperationRepository) {
        self.cancelledID = cancelledID
        self.store = store
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        sentOperationIDs.append(operation.operation.id)
        try await store.markTerminalFailure(clientOperationID: cancelledID, errorDescription: "cancelled", at: Date())
        return .succeeded
    }
}

private actor PurgingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitDailyAnswer
    private let purger: SwiftDataLocalPrivacyRecordStore
    private(set) var sentOperationIDs: [UUID] = []

    init(purger: SwiftDataLocalPrivacyRecordStore) {
        self.purger = purger
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        sentOperationIDs.append(operation.operation.id)
        try await purger.purgeRelationshipContent(ownerUserID: operation.ownerUserID, clearAccessSnapshot: false)
        return .succeeded
    }
}

private func testUUID(_ rawValue: String) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        preconditionFailure("Invalid test UUID: \(rawValue)")
    }
    return uuid
}
