import Foundation
import SwiftData

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

    /// Removes a write the user took back before it was ever tried, with everything it
    /// carries (a message's photos and recording). Returns false and keeps the write when
    /// it is sending now, finished, or was tried before, since the server may already have it
    /// when the answer got lost.
    func discardUnsent(clientOperationID: UUID) async throws -> Bool
}

extension PendingSyncOperationPersisting {
    /// Stores that keep no payload of their own only mark the write as given up. The drain
    /// refuses to start a write that gave up.
    func discardUnsent(clientOperationID: UUID) async throws -> Bool {
        try await markTerminalFailure(
            clientOperationID: clientOperationID,
            errorDescription: "The user took the write back before it was sent",
            at: Date()
        )
        return true
    }
}

nonisolated enum PendingSyncOperationRetention {
    /// How long a write that gave up stays on the phone before it is deleted.
    static let terminal: TimeInterval = 7 * 24 * 60 * 60
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
        let queued = SyncPendingOperationStatus.queued.rawValue
        let retrying = SyncPendingOperationStatus.retrying.rawValue
        let failedRetryable = SyncPendingOperationStatus.failedRetryable.rawValue
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
                    && (operation.statusRawValue == queued
                        || operation.statusRawValue == retrying
                        || operation.statusRawValue == failedRetryable)
            },
            sortBy: [
                SortDescriptor(\.localCreatedAt),
                SortDescriptor(\.clientSequence)
            ]
        )

        // Only the retry date is left to check here, on the few rows that failed.
        let operations = try context.fetch(descriptor)
            .filter { operation in
                operation.status != .failedRetryable || operation.nextRetryAt.map { $0 <= now } ?? true
            }
            .prefix(limit)

        return operations.map(Self.snapshot(from:))
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) throws -> Date? {
        let context = ModelContext(container)
        let retrying = SyncPendingOperationStatus.retrying.rawValue
        let failedRetryable = SyncPendingOperationStatus.failedRetryable.rawValue
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
                    && (operation.statusRawValue == retrying || operation.statusRawValue == failedRetryable)
            }
        )

        return try context.fetch(descriptor)
            .map { operation in
                operation.status == .retrying ? now : operation.nextRetryAt ?? now
            }
            .min()
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) throws -> [PendingSyncOperationSnapshot] {
        let context = ModelContext(container)
        let kindRawValue = kind.rawValue
        let queued = SyncPendingOperationStatus.queued.rawValue
        let sending = SyncPendingOperationStatus.sending.rawValue
        let retrying = SyncPendingOperationStatus.retrying.rawValue
        let failedRetryable = SyncPendingOperationStatus.failedRetryable.rawValue
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
                    && operation.operationKindRawValue == kindRawValue
                    && (operation.statusRawValue == queued
                        || operation.statusRawValue == sending
                        || operation.statusRawValue == retrying
                        || operation.statusRawValue == failedRetryable)
            },
            sortBy: [
                SortDescriptor(\.localCreatedAt),
                SortDescriptor(\.clientSequence)
            ]
        )

        return try context.fetch(descriptor).map(Self.snapshot(from:))
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
        // No post. A write that starts sending is still waiting, so no screen changes.
        try context.save()
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

    /// Deletes the writes the server accepted, and the ones that gave up more than
    /// `terminalRetention` ago. No screen reads either kind, and neither changes
    /// what a screen shows, so this posts nothing.
    func deleteCompleted(ownerUserID: UUID) throws {
        let context = ModelContext(container)
        let succeeded = SyncPendingOperationStatus.succeeded.rawValue
        let failedTerminal = SyncPendingOperationStatus.failedTerminal.rawValue
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID
                    && (operation.statusRawValue == succeeded || operation.statusRawValue == failedTerminal)
            }
        )

        let cutoff = Date().addingTimeInterval(-PendingSyncOperationRetention.terminal)
        let deletable = try context.fetch(descriptor).filter { operation in
            operation.status == .succeeded || (operation.lastAttemptAt ?? .distantPast) < cutoff
        }
        guard !deletable.isEmpty else {
            return
        }
        deletable.forEach(context.delete)
        try context.save()
    }

    func discardUnsent(clientOperationID: UUID) throws -> Bool {
        let context = ModelContext(container)
        guard let operation = try fetchOperation(id: clientOperationID, in: context) else { return true }
        guard operation.status != .sending, operation.status != .succeeded, operation.attemptCount == 0
        else { return false }
        let ownerUserID = operation.ownerUserID
        context.delete(operation)
        try context.save()
        LocalStoreChanges.post(.pendingOperations, ownerUserID: ownerUserID)
        return true
    }

    /// A write that was sending when the app stopped goes back to waiting. Its
    /// state is still "not sent yet" for every screen, so this posts nothing.
    func resetInFlight(ownerUserID: UUID) throws {
        let context = ModelContext(container)
        let sending = SyncPendingOperationStatus.sending.rawValue
        let descriptor = FetchDescriptor<LocalPendingSyncOperation>(
            predicate: #Predicate { operation in
                operation.ownerUserID == ownerUserID && operation.statusRawValue == sending
            }
        )

        let interrupted = try context.fetch(descriptor)
        guard !interrupted.isEmpty else {
            return
        }
        for operation in interrupted {
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
