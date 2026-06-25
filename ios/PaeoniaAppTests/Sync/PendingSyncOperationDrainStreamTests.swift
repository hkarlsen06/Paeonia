import Foundation
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
    ) async throws -> PendingSyncOperationSendResult {
        sentIDs.append(operation.operation.id)
        return .succeeded
    }
}
