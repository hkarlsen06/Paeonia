import Foundation

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
