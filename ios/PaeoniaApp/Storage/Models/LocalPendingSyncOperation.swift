import Foundation
import SwiftData

@Model
final class LocalPendingSyncOperation {
    @Attribute(.unique) var clientOperationID: UUID
    var ownerUserID: UUID
    var clientID: UUID
    var clientSequence: Int64
    var localCreatedAt: Date
    var operationKindRawValue: String
    var idempotencyScope: String
    var requestHash: Data?
    var requestData: Data?
    var statusRawValue: String
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    var lastError: String?
    var completedAt: Date?

    init(
        ownerUserID: UUID,
        operation: SyncClientOperation,
        operationKind: SyncPendingOperationKind,
        idempotencyScope: String,
        requestHash: Data? = nil,
        requestData: Data? = nil,
        status: SyncPendingOperationStatus = .queued
    ) {
        self.clientOperationID = operation.id
        self.ownerUserID = ownerUserID
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.operationKindRawValue = operationKind.rawValue
        self.idempotencyScope = idempotencyScope
        self.requestHash = requestHash
        self.requestData = requestData
        self.statusRawValue = status.rawValue
        self.attemptCount = 0
    }

    var operationKind: SyncPendingOperationKind? {
        get { SyncPendingOperationKind(rawValue: operationKindRawValue) }
        set { operationKindRawValue = newValue?.rawValue ?? operationKindRawValue }
    }

    var status: SyncPendingOperationStatus {
        get { SyncPendingOperationStatus(rawValue: statusRawValue) ?? .queued }
        set { statusRawValue = newValue.rawValue }
    }

    var operationEnvelope: SyncClientOperation {
        SyncClientOperation(
            id: clientOperationID,
            clientID: clientID,
            clientSequence: clientSequence,
            localCreatedAt: localCreatedAt
        )
    }

    func markSending(at date: Date = Date()) {
        status = .sending
        attemptCount += 1
        lastAttemptAt = date
        lastError = nil
    }

    func markRetryableFailure(
        _ errorDescription: String,
        nextRetryAt: Date?,
        at date: Date = Date()
    ) {
        status = .failedRetryable
        lastAttemptAt = date
        self.nextRetryAt = nextRetryAt
        lastError = errorDescription
    }

    func markTerminalFailure(_ errorDescription: String, at date: Date = Date()) {
        status = .failedTerminal
        lastAttemptAt = date
        lastError = errorDescription
    }

    func markSucceeded(at date: Date = Date()) {
        status = .succeeded
        completedAt = date
        lastAttemptAt = date
        nextRetryAt = nil
        lastError = nil
    }
}
