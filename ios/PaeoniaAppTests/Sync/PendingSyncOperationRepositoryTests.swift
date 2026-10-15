import Foundation
import SwiftData
import Testing
@testable import PaeoniaApp

struct PendingSyncOperationRepositoryTests {
    private let owner = UUID()

    @Test func queriesKeepOtherUsersAndFinishedWritesOut() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let queued = try await enqueue(1, in: repository)
        let sending = try await enqueue(2, in: repository)
        let succeeded = try await enqueue(3, in: repository)
        let terminal = try await enqueue(4, in: repository)
        let otherUser = try await enqueue(5, owner: UUID(), in: repository)
        try await repository.markSending(clientOperationID: sending.id, at: Date())
        try await repository.markSending(clientOperationID: succeeded.id, at: Date())
        try await repository.markSucceeded(clientOperationID: succeeded.id, at: Date())
        try await repository.markTerminalFailure(clientOperationID: terminal.id, errorDescription: "no", at: Date())

        let ready = try await repository.readyOperations(ownerUserID: owner, limit: 10, now: Date())
        let inFlight = try await repository.inFlightOperations(ownerUserID: owner, kind: .submitDailyAnswer)

        #expect(ready.map(\.operation.id) == [queued.id])
        #expect(inFlight.map(\.operation.id) == [queued.id, sending.id])
        #expect(!inFlight.contains { $0.operation.id == otherUser.id })
    }

    @Test func nextPendingOperationDateIsTheEarliestRetry() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let early = try await enqueue(1, in: repository)
        let late = try await enqueue(2, in: repository)
        _ = try await enqueue(3, in: repository)
        let now = Date()
        for (operation, delay) in [(early, 60.0), (late, 300.0)] {
            try await repository.markSending(clientOperationID: operation.id, at: now)
            try await repository.markRetryableFailure(
                clientOperationID: operation.id,
                errorDescription: "offline",
                nextRetryAt: now.addingTimeInterval(delay),
                at: now
            )
        }

        let next = try await repository.nextPendingOperationDate(ownerUserID: owner, now: now)

        #expect(next == now.addingTimeInterval(60))
    }

    @Test func requestDataSurvivesTheRoundTripThroughTheStore() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let payload = Data(repeating: 7, count: 300_000)
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1, localCreatedAt: Date())
        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "test:\(operation.id)",
                requestData: payload
            )
        )

        let ready = try await repository.readyOperations(ownerUserID: owner, limit: 10, now: Date())

        #expect(ready.first?.requestData == payload)
    }

    @Test func deleteCompletedKeepsRecentFailuresAndDropsOldOnes() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let oldFailure = try await enqueue(1, in: repository)
        let recentFailure = try await enqueue(2, in: repository)
        let finished = try await enqueue(3, in: repository)
        let waiting = try await enqueue(4, in: repository)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3_600)
        try await repository.markTerminalFailure(
            clientOperationID: oldFailure.id,
            errorDescription: "x",
            at: eightDaysAgo
        )
        try await repository.markTerminalFailure(
            clientOperationID: recentFailure.id,
            errorDescription: "x",
            at: Date()
        )
        try await repository.markSending(clientOperationID: finished.id, at: Date())
        try await repository.markSucceeded(clientOperationID: finished.id, at: Date())

        try await repository.deleteCompleted(ownerUserID: owner)

        let remaining = try ModelContext(store.container).fetch(FetchDescriptor<LocalPendingSyncOperation>())
        #expect(Set(remaining.map(\.clientOperationID)) == [recentFailure.id, waiting.id])
    }

    @Test func resetInFlightPutsInterruptedWritesBackInTheQueue() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataPendingSyncOperationRepository(container: store.container)
        let interrupted = try await enqueue(1, in: repository)
        try await repository.markSending(clientOperationID: interrupted.id, at: Date())

        try await repository.resetInFlight(ownerUserID: owner)

        let ready = try await repository.readyOperations(ownerUserID: owner, limit: 10, now: Date())
        #expect(ready.map(\.operation.id) == [interrupted.id])
        #expect(ready.first?.status == .retrying)
    }

    @Test func onlyChangesAScreenCanSeePostToTheStore() async throws {
        let repository = InMemoryPendingSyncOperationRepository()
        let operation = try await enqueue(1, in: repository)
        let marker = UUID()
        let stream = LocalStoreChanges.changes(in: .pendingOperations)
            .filter { $0.ownerUserID == owner || $0.ownerUserID == marker }

        // Starting to send, cleanup and a restart reset change nothing on screen.
        try await repository.markSending(clientOperationID: operation.id, at: Date())
        try await repository.resetInFlight(ownerUserID: owner)
        try await repository.deleteCompleted(ownerUserID: owner)
        LocalStoreChanges.post(.pendingOperations, ownerUserID: marker)
        try await repository.markSending(clientOperationID: operation.id, at: Date())
        try await repository.markSucceeded(clientOperationID: operation.id, at: Date())

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.ownerUserID == marker)
        #expect(await iterator.next()?.ownerUserID == owner)
    }

    @discardableResult
    private func enqueue(
        _ sequence: Int,
        owner: UUID? = nil,
        in repository: any PendingSyncOperationPersisting
    ) async throws -> SyncClientOperation {
        let operation = SyncClientOperation(
            clientID: UUID(),
            clientSequence: Int64(sequence),
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + sequence))
        )
        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner ?? self.owner,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "test:\(operation.id)"
            )
        )
        return operation
    }
}
