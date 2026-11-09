import Foundation
@testable import PaeoniaApp

/// A storage-read failure at the I/O boundary. All successful operations use the real repository.
actor ReadFailingMediaAlternativeOutbox: PendingSyncOperationPersisting {
    enum ReadError: Error { case unavailable }
    private let base: any PendingSyncOperationPersisting
    private var readsFail = false
    init(base: any PendingSyncOperationPersisting) { self.base = base }
    func failReads(_ fail: Bool) { readsFail = fail }

    func enqueue(_ request: PendingSyncOperationRequest) async throws { try await base.enqueue(request) }
    func inFlightOperations(ownerUserID: UUID, kind: SyncPendingOperationKind) async throws
        -> [PendingSyncOperationSnapshot] {
        if readsFail { throw ReadError.unavailable }
        return try await base.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }
    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws -> [PendingSyncOperationSnapshot] {
        try await base.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }
    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await base.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }
    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSending(clientOperationID: clientOperationID, at: date)
    }
    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSucceeded(clientOperationID: clientOperationID, at: date)
    }
    func markRetryableFailure(clientOperationID: UUID, failure: PendingSyncFailure, nextRetryAt: Date?, at date: Date)
        async throws {
        try await base.markRetryableFailure(clientOperationID: clientOperationID, failure: failure,
                                             nextRetryAt: nextRetryAt, at: date)
    }
    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date) async throws {
        try await base.markTerminalFailure(
            clientOperationID: clientOperationID, errorDescription: errorDescription, at: date
        )
    }
    func deleteCompleted(ownerUserID: UUID) async throws { try await base.deleteCompleted(ownerUserID: ownerUserID) }
    func resetInFlight(ownerUserID: UUID) async throws { try await base.resetInFlight(ownerUserID: ownerUserID) }
    func discardUnsent(clientOperationID: UUID) async throws -> Bool {
        try await base.discardUnsent(clientOperationID: clientOperationID)
    }
}
