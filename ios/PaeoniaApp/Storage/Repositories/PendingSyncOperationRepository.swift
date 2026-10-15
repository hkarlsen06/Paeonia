import Foundation
import SwiftData

nonisolated struct PendingSyncOperationRequest: Equatable, Sendable {
    let ownerUserID: UUID
    let operation: SyncClientOperation
    let operationKind: SyncPendingOperationKind
    let idempotencyScope: String
    let requestHash: Data?
    let requestData: Data?

    init(
        ownerUserID: UUID,
        operation: SyncClientOperation,
        operationKind: SyncPendingOperationKind,
        idempotencyScope: String,
        requestHash: Data? = nil,
        requestData: Data? = nil
    ) {
        self.ownerUserID = ownerUserID
        self.operation = operation
        self.operationKind = operationKind
        self.idempotencyScope = idempotencyScope
        self.requestHash = requestHash
        self.requestData = requestData
    }
}

/// `markSending` throws this when the operation was cancelled or finished after
/// the drain read its batch.
nonisolated enum PendingSyncOperationClaimError: Error, Equatable, Sendable {
    case notPending
}

nonisolated struct PendingSyncOperationSnapshot: Equatable, Sendable {
    let ownerUserID: UUID
    let operation: SyncClientOperation
    let operationKind: SyncPendingOperationKind?
    let idempotencyScope: String
    let requestHash: Data?
    let requestData: Data?
    let status: SyncPendingOperationStatus
    let attemptCount: Int
    let lastAttemptAt: Date?
    let nextRetryAt: Date?
    let lastError: String?
    let completedAt: Date?
}

extension PendingSyncOperationSnapshot {
    /// A try has ended without success. `lastError` covers the time after it,
    /// and the attempt count covers the next try, which clears `lastError`.
    ///
    /// Every write waits in the queue for a moment, also online. Show "Saved on
    /// this phone. We'll send it when you're online." only when this is true, so
    /// a normal send never flashes that line.
    nonisolated var hasFailedAttempt: Bool {
        lastError != nil || attemptCount > 1
    }
}

protocol PendingSyncOperationPersisting: Actor {
    func enqueue(_ request: PendingSyncOperationRequest) async throws

    func readyOperations(
        ownerUserID: UUID,
        limit: Int,
        now: Date
    ) async throws -> [PendingSyncOperationSnapshot]
    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date?

    /// Operations of a kind that haven't finished yet — queued, sending, retrying, or
    /// waiting to retry. Used to show a "still sending" state that survives relaunch.
    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot]

    func markSending(clientOperationID: UUID, at date: Date) async throws
    func markSucceeded(clientOperationID: UUID, at date: Date) async throws
    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) async throws
    func markTerminalFailure(
        clientOperationID: UUID,
        errorDescription: String,
        at date: Date
    ) async throws
    func deleteCompleted(ownerUserID: UUID) async throws
    func resetInFlight(ownerUserID: UUID) async throws
}

actor SwiftDataPendingSyncOperationRepository: PendingSyncOperationPersisting {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func enqueue(_ request: PendingSyncOperationRequest) throws {
        let context = ModelContext(container)

        if try fetchOperation(id: request.operation.id, in: context) != nil {
            return
        }

        context.insert(
            LocalPendingSyncOperation(
                ownerUserID: request.ownerUserID,
                operation: request.operation,
                operationKind: request.operationKind,
                idempotencyScope: request.idempotencyScope,
                requestHash: request.requestHash,
                requestData: request.requestData
            )
        )
        try context.save()
        LocalStoreChanges.post(.pendingOperations, ownerUserID: request.ownerUserID)
    }

    func readyOperations(
        ownerUserID: UUID,
        limit: Int,
        now: Date
    ) throws -> [PendingSyncOperationSnapshot] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
            },
            sortBy: [
                SortDescriptor(\.localCreatedAt),
                SortDescriptor(\.clientSequence)
            ]
        )

        let operations = try context.fetch(descriptor)
            .filter { operation in
                switch operation.status {
                case .queued, .retrying:
                    return true
                case .failedRetryable:
                    return operation.nextRetryAt.map { $0 <= now } ?? true
                case .sending, .failedTerminal, .succeeded:
                    return false
                }
            }
            .prefix(limit)

        return operations.map(Self.snapshot(from:))
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) throws -> Date? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
            }
        )

        return try context.fetch(descriptor)
            .compactMap { operation -> Date? in
                switch operation.status {
                case .retrying:
                    return now
                case .failedRetryable:
                    return operation.nextRetryAt ?? now
                case .queued, .sending, .failedTerminal, .succeeded:
                    return nil
                }
            }
            .min()
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) throws -> [PendingSyncOperationSnapshot] {
        let context = ModelContext(container)
        let kindRawValue = kind.rawValue
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID && operation.operationKindRawValue == kindRawValue
            },
            sortBy: [
                SortDescriptor(\.localCreatedAt),
                SortDescriptor(\.clientSequence)
            ]
        )

        return try context.fetch(descriptor)
            .filter { operation in
                switch operation.status {
                case .queued, .sending, .retrying, .failedRetryable:
                    return true
                case .failedTerminal, .succeeded:
                    return false
                }
            }
            .map(Self.snapshot(from:))
    }

    func markSending(clientOperationID: UUID, at date: Date) throws {
        let context = ModelContext(container)
        // The batch was read earlier. An operation cancelled, finished, or purged
        // since then must not be sent.
        guard let operation = try fetchOperation(id: clientOperationID, in: context),
              operation.status != .failedTerminal,
              operation.status != .succeeded
        else {
            throw PendingSyncOperationClaimError.notPending
        }
        operation.markSending(at: date)
        try context.save()
        LocalStoreChanges.post(.pendingOperations, ownerUserID: operation.ownerUserID)
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) throws {
        try update(clientOperationID: clientOperationID) { operation in
            operation.markSucceeded(at: date)
        }
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) throws {
        try update(clientOperationID: clientOperationID) { operation in
            operation.markRetryableFailure(
                errorDescription,
                nextRetryAt: nextRetryAt,
                at: date
            )
        }
    }

    func markTerminalFailure(
        clientOperationID: UUID,
        errorDescription: String,
        at date: Date
    ) throws {
        try update(clientOperationID: clientOperationID) { operation in
            operation.markTerminalFailure(errorDescription, at: date)
        }
    }

    func deleteCompleted(ownerUserID: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
            }
        )

        let completed = try context.fetch(descriptor).filter { $0.status == .succeeded }
        guard !completed.isEmpty else {
            return
        }
        completed.forEach(context.delete)

        try context.save()
        LocalStoreChanges.post(.pendingOperations, ownerUserID: ownerUserID)
    }

    func resetInFlight(ownerUserID: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
            }
        )

        for operation in try context.fetch(descriptor) where operation.status == .sending {
            operation.status = .retrying
        }

        try context.save()
        LocalStoreChanges.post(.pendingOperations, ownerUserID: ownerUserID)
    }

    private func update(
        clientOperationID: UUID,
        mutate: (LocalPendingSyncOperation) -> Void
    ) throws {
        let context = ModelContext(container)

        guard let operation = try fetchOperation(id: clientOperationID, in: context) else {
            return
        }

        mutate(operation)
        try context.save()
        LocalStoreChanges.post(.pendingOperations, ownerUserID: operation.ownerUserID)
    }

    private func fetchOperation(
        id: UUID,
        in context: ModelContext
    ) throws -> LocalPendingSyncOperation? {
        var descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.clientOperationID == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func snapshot(
        from operation: LocalPendingSyncOperation
    ) -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: operation.ownerUserID,
            operation: operation.operationEnvelope,
            operationKind: operation.operationKind,
            idempotencyScope: operation.idempotencyScope,
            requestHash: operation.requestHash,
            requestData: operation.requestData,
            status: operation.status,
            attemptCount: operation.attemptCount,
            lastAttemptAt: operation.lastAttemptAt,
            nextRetryAt: operation.nextRetryAt,
            lastError: operation.lastError,
            completedAt: operation.completedAt
        )
    }
}
