import Foundation
@testable import PaeoniaApp

/// Fails or holds the local durable-write boundary while retaining the real outbox behavior.
actor RetainedContentPendingStore: PendingSyncOperationPersisting {
    let base = InMemoryPendingSyncOperationRepository()
    private(set) var attempts: [PendingSyncOperationRequest] = []
    private var failureAttempt: Int?
    private var writesBeforeFailure = false
    private var holdsNext = false
    private var release: CheckedContinuation<Void, Never>?

    func fail(at attempt: Int, afterWriting: Bool = false) {
        failureAttempt = attempt
        writesBeforeFailure = afterWriting
    }

    func holdNext() { holdsNext = true }
    var isHeld: Bool { release != nil }
    func resume() { release?.resume(); release = nil }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        attempts.append(request)
        let shouldFail = attempts.count == failureAttempt
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { release = $0 }
        }
        if shouldFail && !writesBeforeFailure { throw CocoaError(.fileWriteOutOfSpace) }
        try await base.enqueue(request)
        if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
    }

    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws -> [PendingSyncOperationSnapshot] {
        try await base.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }
    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await base.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }
    func inFlightOperations(
        ownerUserID: UUID, kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        try await base.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }
    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSending(clientOperationID: clientOperationID, at: date)
    }
    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await base.markSucceeded(clientOperationID: clientOperationID, at: date)
    }
    func markRetryableFailure(
        clientOperationID: UUID, errorDescription: String, nextRetryAt: Date?, at date: Date
    ) async throws {
        try await base.markRetryableFailure(
            clientOperationID: clientOperationID, errorDescription: errorDescription, nextRetryAt: nextRetryAt, at: date
        )
    }
    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date) async throws {
        try await base.markTerminalFailure(
            clientOperationID: clientOperationID, errorDescription: errorDescription, at: date
        )
    }
    func deleteCompleted(ownerUserID: UUID) async throws { try await base.deleteCompleted(ownerUserID: ownerUserID) }
    func resetInFlight(ownerUserID: UUID) async throws { try await base.resetInFlight(ownerUserID: ownerUserID) }
}
