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

protocol PendingSyncOperationPersisting: Actor {
    func enqueue(_ request: PendingSyncOperationRequest) async throws

    func readyOperations(
        ownerUserID: UUID,
        limit: Int,
        now: Date
    ) async throws -> [PendingSyncOperationSnapshot]

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

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
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
    }

    func readyOperations(
        ownerUserID: UUID,
        limit: Int,
        now: Date
    ) async throws -> [PendingSyncOperationSnapshot] {
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

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
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

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try update(clientOperationID: clientOperationID) { operation in
            operation.markSending(at: date)
        }
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try update(clientOperationID: clientOperationID) { operation in
            operation.markSucceeded(at: date)
        }
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) async throws {
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
    ) async throws {
        try update(clientOperationID: clientOperationID) { operation in
            operation.markTerminalFailure(errorDescription, at: date)
        }
    }

    func deleteCompleted(ownerUserID: UUID) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
            }
        )

        for operation in try context.fetch(descriptor) where operation.status == .succeeded {
            context.delete(operation)
        }

        try context.save()
    }

    func resetInFlight(ownerUserID: UUID) async throws {
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

actor InMemoryPendingSyncOperationRepository: PendingSyncOperationPersisting {
    private var operations: [UUID: PendingSyncOperationSnapshot] = [:]

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        operations[request.operation.id] = operations[request.operation.id] ?? PendingSyncOperationSnapshot(
            ownerUserID: request.ownerUserID,
            operation: request.operation,
            operationKind: request.operationKind,
            idempotencyScope: request.idempotencyScope,
            requestHash: request.requestHash,
            requestData: request.requestData,
            status: .queued,
            attemptCount: 0,
            lastAttemptAt: nil,
            nextRetryAt: nil,
            lastError: nil,
            completedAt: nil
        )
    }

    func readyOperations(
        ownerUserID: UUID,
        limit: Int,
        now: Date
    ) async throws -> [PendingSyncOperationSnapshot] {
        operations.values
            .filter { operation in
                guard operation.ownerUserID == ownerUserID else {
                    return false
                }

                switch operation.status {
                case .queued, .retrying:
                    return true
                case .failedRetryable:
                    return operation.nextRetryAt.map { $0 <= now } ?? true
                case .sending, .failedTerminal, .succeeded:
                    return false
                }
            }
            .sorted {
                if $0.operation.localCreatedAt == $1.operation.localCreatedAt {
                    return $0.operation.clientSequence < $1.operation.clientSequence
                }

                return $0.operation.localCreatedAt < $1.operation.localCreatedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        operations.values
            .filter { $0.ownerUserID == ownerUserID && $0.operationKind == kind }
            .filter { operation in
                switch operation.status {
                case .queued, .sending, .retrying, .failedRetryable:
                    return true
                case .failedTerminal, .succeeded:
                    return false
                }
            }
            .sorted {
                if $0.operation.localCreatedAt == $1.operation.localCreatedAt {
                    return $0.operation.clientSequence < $1.operation.clientSequence
                }
                return $0.operation.localCreatedAt < $1.operation.localCreatedAt
            }
    }

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                status: .sending,
                attemptCount: operation.attemptCount + 1,
                lastAttemptAt: date,
                nextRetryAt: operation.nextRetryAt,
                lastError: nil,
                completedAt: operation.completedAt
            )
        }
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                status: .succeeded,
                attemptCount: operation.attemptCount,
                lastAttemptAt: date,
                nextRetryAt: nil,
                lastError: nil,
                completedAt: date
            )
        }
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) async throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                status: .failedRetryable,
                attemptCount: operation.attemptCount,
                lastAttemptAt: date,
                nextRetryAt: nextRetryAt,
                lastError: errorDescription,
                completedAt: operation.completedAt
            )
        }
    }

    func markTerminalFailure(
        clientOperationID: UUID,
        errorDescription: String,
        at date: Date
    ) async throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                status: .failedTerminal,
                attemptCount: operation.attemptCount,
                lastAttemptAt: date,
                nextRetryAt: operation.nextRetryAt,
                lastError: errorDescription,
                completedAt: operation.completedAt
            )
        }
    }

    func deleteCompleted(ownerUserID: UUID) async throws {
        operations = operations.filter {
            $0.value.ownerUserID != ownerUserID || $0.value.status != .succeeded
        }
    }

    func resetInFlight(ownerUserID: UUID) async throws {
        for operation in operations.values
            where operation.ownerUserID == ownerUserID && operation.status == .sending {
            operations[operation.operation.id] = snapshot(
                from: operation,
                status: .retrying,
                attemptCount: operation.attemptCount,
                lastAttemptAt: operation.lastAttemptAt,
                nextRetryAt: operation.nextRetryAt,
                lastError: operation.lastError,
                completedAt: operation.completedAt
            )
        }
    }

    private func update(
        id: UUID,
        transform: (PendingSyncOperationSnapshot) -> PendingSyncOperationSnapshot
    ) {
        guard let operation = operations[id] else {
            return
        }

        operations[id] = transform(operation)
    }

    private func snapshot(
        from operation: PendingSyncOperationSnapshot,
        status: SyncPendingOperationStatus,
        attemptCount: Int,
        lastAttemptAt: Date?,
        nextRetryAt: Date?,
        lastError: String?,
        completedAt: Date?
    ) -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: operation.ownerUserID,
            operation: operation.operation,
            operationKind: operation.operationKind,
            idempotencyScope: operation.idempotencyScope,
            requestHash: operation.requestHash,
            requestData: operation.requestData,
            status: status,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttemptAt,
            nextRetryAt: nextRetryAt,
            lastError: lastError,
            completedAt: completedAt
        )
    }
}
