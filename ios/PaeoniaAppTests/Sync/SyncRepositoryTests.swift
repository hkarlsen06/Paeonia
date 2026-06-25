import Foundation
import Testing
@testable import PaeoniaApp

struct SyncRepositoryTests {
    @Test func syncStateRepositoryPersistsCursorAndFailures() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataSyncStateRepository(container: store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let tieID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let scope = SyncStreamScope(kind: .user)
        let cursor = SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 200),
            tieID: tieID
        )

        try await repository.markAttempted(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: .relationship,
            at: Date(timeIntervalSince1970: 100)
        )
        try await repository.markSucceeded(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: .relationship,
            cursor: cursor,
            at: Date(timeIntervalSince1970: 210)
        )
        try await repository.markFailed(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: .relationship,
            errorDescription: "Network unavailable",
            at: Date(timeIntervalSince1970: 220)
        )

        let snapshots = try await repository.snapshots(ownerUserID: ownerUserID)

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.cursor == cursor)
        #expect(snapshots.first?.lastSyncError == "Network unavailable")
    }

    @Test func pendingOperationRepositoryReturnsReadyOperationsInOrder() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let firstOperation = try operation(
            id: "22222222-2222-2222-2222-222222222222",
            sequence: 2,
            createdAt: 200
        )
        let secondOperation = try operation(
            id: "33333333-3333-3333-3333-333333333333",
            sequence: 1,
            createdAt: 100
        )

        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: firstOperation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(firstOperation.id)"
            )
        )
        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: secondOperation,
                operationKind: .createPendingMediaUpload,
                idempotencyScope: "media:\(secondOperation.id)"
            )
        )

        let readyOperations = try await repository.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 300)
        )

        #expect(readyOperations.map(\.operation.id) == [
            secondOperation.id,
            firstOperation.id
        ])
    }

    @Test func pendingOperationRepositoryRetriesFailedOperationsAfterBackoff() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let pendingOperation = try operation(
            id: "22222222-2222-2222-2222-222222222222",
            sequence: 1,
            createdAt: 100
        )

        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: pendingOperation,
                operationKind: .sendThreadMessage,
                idempotencyScope: "thread:\(pendingOperation.id)"
            )
        )
        try await repository.markSending(
            clientOperationID: pendingOperation.id,
            at: Date(timeIntervalSince1970: 110)
        )
        try await repository.markRetryableFailure(
            clientOperationID: pendingOperation.id,
            errorDescription: "Offline",
            nextRetryAt: Date(timeIntervalSince1970: 200),
            at: Date(timeIntervalSince1970: 120)
        )

        let beforeBackoff = try await repository.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 150)
        )
        let afterBackoff = try await repository.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 210)
        )

        #expect(beforeBackoff.isEmpty)
        #expect(afterBackoff.map(\.operation.id) == [pendingOperation.id])
    }

    @Test func pendingOperationRepositoryDoesNotStarveReadyRowsBehindCompletedRows() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        for index in 0..<8 {
            let completedOperation = SyncClientOperation(
                id: UUID(),
                clientID: ownerUserID,
                clientSequence: Int64(index),
                localCreatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            try await repository.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: ownerUserID,
                    operation: completedOperation,
                    operationKind: .sendThreadMessage,
                    idempotencyScope: "completed:\(completedOperation.id)"
                )
            )
            try await repository.markSending(
                clientOperationID: completedOperation.id,
                at: Date(timeIntervalSince1970: 100)
            )
            try await repository.markSucceeded(
                clientOperationID: completedOperation.id,
                at: Date(timeIntervalSince1970: 101)
            )
        }

        let queuedOperation = SyncClientOperation(
            id: UUID(),
            clientID: ownerUserID,
            clientSequence: 9,
            localCreatedAt: Date(timeIntervalSince1970: 9)
        )
        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: queuedOperation,
                operationKind: .sendThreadMessage,
                idempotencyScope: "queued:\(queuedOperation.id)"
            )
        )

        let readyOperations = try await repository.readyOperations(
            ownerUserID: ownerUserID,
            limit: 1,
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(readyOperations.map(\.operation.id) == [queuedOperation.id])
    }

    private func operation(
        id: String,
        sequence: Int64,
        createdAt: TimeInterval
    ) throws -> SyncClientOperation {
        SyncClientOperation(
            id: try #require(UUID(uuidString: id)),
            clientID: try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999")),
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}
