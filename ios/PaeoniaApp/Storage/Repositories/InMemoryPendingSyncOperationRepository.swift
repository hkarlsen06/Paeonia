import Foundation

actor InMemoryPendingSyncOperationRepository: PendingSyncOperationPersisting {
    private var operations: [UUID: PendingSyncOperationSnapshot] = [:]

    func enqueue(_ request: PendingSyncOperationRequest) throws {
        defer { LocalStoreChanges.post(.pendingOperations, ownerUserID: request.ownerUserID) }
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
    ) throws -> [PendingSyncOperationSnapshot] {
        let ready = operations.values
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
        return Array(ready.prefix(limit))
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) throws -> Date? {
        operations.values
            .filter { $0.ownerUserID == ownerUserID }
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

    func markSending(clientOperationID: UUID, at date: Date) throws {
        guard let status = operations[clientOperationID]?.status,
              status != .failedTerminal,
              status != .succeeded
        else {
            throw PendingSyncOperationClaimError.notPending
        }
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                progress: Progress(
                    status: .sending,
                    attemptCount: operation.attemptCount + 1,
                    lastAttemptAt: date,
                    nextRetryAt: operation.nextRetryAt,
                    lastError: nil,
                    completedAt: operation.completedAt
                )
            )
        }
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                progress: Progress(
                    status: .succeeded,
                    attemptCount: operation.attemptCount,
                    lastAttemptAt: date,
                    nextRetryAt: nil,
                    lastError: nil,
                    completedAt: date
                )
            )
        }
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                progress: Progress(
                    status: .failedRetryable,
                    attemptCount: operation.attemptCount,
                    lastAttemptAt: date,
                    nextRetryAt: nextRetryAt,
                    lastError: errorDescription,
                    completedAt: operation.completedAt
                )
            )
        }
    }

    func markTerminalFailure(
        clientOperationID: UUID,
        errorDescription: String,
        at date: Date
    ) throws {
        update(id: clientOperationID) { operation in
            snapshot(
                from: operation,
                progress: Progress(
                    status: .failedTerminal,
                    attemptCount: operation.attemptCount,
                    lastAttemptAt: date,
                    nextRetryAt: operation.nextRetryAt,
                    lastError: errorDescription,
                    completedAt: operation.completedAt
                )
            )
        }
    }

    func deleteCompleted(ownerUserID: UUID) throws {
        operations = operations.filter {
            $0.value.ownerUserID != ownerUserID || $0.value.status != .succeeded
        }
        LocalStoreChanges.post(.pendingOperations, ownerUserID: ownerUserID)
    }

    func resetInFlight(ownerUserID: UUID) throws {
        for operation in operations.values
            where operation.ownerUserID == ownerUserID && operation.status == .sending {
            operations[operation.operation.id] = snapshot(
                from: operation,
                progress: Progress(
                    status: .retrying,
                    attemptCount: operation.attemptCount,
                    lastAttemptAt: operation.lastAttemptAt,
                    nextRetryAt: operation.nextRetryAt,
                    lastError: operation.lastError,
                    completedAt: operation.completedAt
                )
            )
        }
        LocalStoreChanges.post(.pendingOperations, ownerUserID: ownerUserID)
    }

    private func update(
        id: UUID,
        transform: (PendingSyncOperationSnapshot) -> PendingSyncOperationSnapshot
    ) {
        guard let operation = operations[id] else {
            return
        }

        operations[id] = transform(operation)
        LocalStoreChanges.post(.pendingOperations, ownerUserID: operation.ownerUserID)
    }

    /// The fields a send changes. Everything else on the snapshot stays as it was.
    private struct Progress {
        let status: SyncPendingOperationStatus
        let attemptCount: Int
        let lastAttemptAt: Date?
        let nextRetryAt: Date?
        let lastError: String?
        let completedAt: Date?
    }

    private func snapshot(
        from operation: PendingSyncOperationSnapshot,
        progress: Progress
    ) -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: operation.ownerUserID,
            operation: operation.operation,
            operationKind: operation.operationKind,
            idempotencyScope: operation.idempotencyScope,
            requestHash: operation.requestHash,
            requestData: operation.requestData,
            status: progress.status,
            attemptCount: progress.attemptCount,
            lastAttemptAt: progress.lastAttemptAt,
            nextRetryAt: progress.nextRetryAt,
            lastError: progress.lastError,
            completedAt: progress.completedAt
        )
    }
}
