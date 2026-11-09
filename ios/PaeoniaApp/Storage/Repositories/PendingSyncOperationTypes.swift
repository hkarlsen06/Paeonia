import Foundation

nonisolated struct PendingSyncOperationRequest: Equatable, Sendable {
    let ownerUserID: UUID
    let operation: SyncClientOperation
    let operationKind: SyncPendingOperationKind
    let idempotencyScope: String
    let requestHash: Data?
    let requestData: Data?
    let privacyToken: LocalPrivacyWriteGuard.Token?

    init(
        ownerUserID: UUID,
        operation: SyncClientOperation,
        operationKind: SyncPendingOperationKind,
        idempotencyScope: String,
        requestHash: Data? = nil,
        requestData: Data? = nil,
        privacyToken: LocalPrivacyWriteGuard.Token? = nil
    ) {
        self.ownerUserID = ownerUserID
        self.operation = operation
        self.operationKind = operationKind
        self.idempotencyScope = idempotencyScope
        self.requestHash = requestHash
        self.requestData = requestData
        self.privacyToken = privacyToken
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
    /// For logs. Screens read `lastFailureKind`.
    let lastError: String?
    /// Set by a failed try that will be retried. Nil after a terminal failure.
    var lastFailureKind: PendingSyncFailureKind?
    let completedAt: Date?
}

/// Why the last try of a queued write did not get through, as a screen needs it.
nonisolated enum PendingSyncFailureKind: String, Sendable {
    /// The phone has no connection (`PaeoniaFailure.offline`).
    case offline
    /// The write waits behind another one, or the server asked it to try later.
    case waiting
    /// Anything that may happen on a working connection, such as a server error,
    /// a refusal or a timeout.
    case other
}

/// A failed try of a queued write that will be retried.
nonisolated struct PendingSyncFailure: Equatable, Sendable {
    let kind: PendingSyncFailureKind
    let description: String

    init(kind: PendingSyncFailureKind, description: String) {
        self.kind = kind
        self.description = description
    }

    init(_ error: any Error) {
        kind = PaeoniaFailure(error) == .offline ? .offline : .other
        description = String(describing: error)
    }

    static let retryLater = PendingSyncFailure(kind: .waiting, description: "Retry later")
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

    /// The last try failed on what may be a working connection. A write that
    /// waits behind an earlier one and a phone with no connection do not count.
    nonisolated var failedWhileOnline: Bool {
        lastFailureKind == .other
    }
}
