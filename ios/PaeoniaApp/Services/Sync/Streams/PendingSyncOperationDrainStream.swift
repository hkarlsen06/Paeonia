import Foundation

nonisolated enum PendingSyncOperationSendResult: Equatable, Sendable {
    case succeeded
    case retry(after: Date?)
    case terminalFailure(String)
}

nonisolated protocol PendingSyncOperationHandling: Sendable {
    nonisolated var operationKind: SyncPendingOperationKind { get }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult
}

nonisolated enum PendingSyncOperationDrainError: Error, Equatable, Sendable {
    case unsupportedOperationKind(String)
}

struct PendingSyncOperationDrainStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .pendingOperations

    private let handlers: [SyncPendingOperationKind: any PendingSyncOperationHandling]
    private let batchSize: Int
    private let retryPolicy: PendingSyncOperationRetryPolicy

    nonisolated init(
        handlers: [any PendingSyncOperationHandling],
        batchSize: Int = 25,
        retryPolicy: PendingSyncOperationRetryPolicy = PendingSyncOperationRetryPolicy()
    ) {
        self.handlers = Dictionary(uniqueKeysWithValues: handlers.map { ($0.operationKind, $0) })
        self.batchSize = batchSize
        self.retryPolicy = retryPolicy
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    func pull(context _: SyncContext) async throws -> SyncCursor? {
        nil
    }

    func push(context: SyncContext) async throws {
        let operations = try await context.pendingOperationStore.readyOperations(
            ownerUserID: context.session.userID,
            limit: batchSize,
            now: Date()
        )

        for operation in operations {
            try Task.checkCancellation()

            guard let operationKind = operation.operationKind,
                let handler = handlers[operationKind] else {
                throw PendingSyncOperationDrainError.unsupportedOperationKind(
                    operation.operationKind?.rawValue ?? "unknown"
                )
            }

            let attemptNumber = operation.attemptCount + 1

            try await context.pendingOperationStore.markSending(
                clientOperationID: operation.operation.id,
                at: Date()
            )

            do {
                switch try await handler.send(operation, context: context) {
                case .succeeded:
                    try await context.pendingOperationStore.markSucceeded(
                        clientOperationID: operation.operation.id,
                        at: Date()
                    )
                case let .retry(nextRetryAt):
                    try await recordRetryOrTerminalFailure(
                        operation: operation,
                        attemptNumber: attemptNumber,
                        errorDescription: "Retry later",
                        nextRetryAt: nextRetryAt,
                        context: context
                    )
                case let .terminalFailure(errorDescription):
                    try await context.pendingOperationStore.markTerminalFailure(
                        clientOperationID: operation.operation.id,
                        errorDescription: errorDescription,
                        at: Date()
                    )
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                try await recordRetryOrTerminalFailure(
                    operation: operation,
                    attemptNumber: attemptNumber,
                    errorDescription: String(describing: error),
                    nextRetryAt: nil,
                    context: context
                )
            }
        }
    }

    private func recordRetryOrTerminalFailure(
        operation: PendingSyncOperationSnapshot,
        attemptNumber: Int,
        errorDescription: String,
        nextRetryAt: Date?,
        context: SyncContext
    ) async throws {
        if retryPolicy.shouldMarkTerminal(attemptNumber: attemptNumber) {
            try await context.pendingOperationStore.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: errorDescription,
                at: Date()
            )
            return
        }

        try await context.pendingOperationStore.markRetryableFailure(
            clientOperationID: operation.operation.id,
            errorDescription: errorDescription,
            nextRetryAt: nextRetryAt ?? retryPolicy.nextRetryDate(
                attemptNumber: attemptNumber,
                now: Date()
            ),
            at: Date()
        )
    }
}

nonisolated struct PendingSyncOperationRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int?
    let baseDelaySeconds: TimeInterval
    let maximumDelaySeconds: TimeInterval

    init(
        maximumAttempts: Int? = nil,
        baseDelaySeconds: TimeInterval = 60,
        maximumDelaySeconds: TimeInterval = 3_600
    ) {
        self.maximumAttempts = maximumAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maximumDelaySeconds = maximumDelaySeconds
    }

    func shouldMarkTerminal(attemptNumber: Int) -> Bool {
        guard let maximumAttempts else {
            return false
        }

        return attemptNumber >= maximumAttempts
    }

    func nextRetryDate(attemptNumber: Int, now: Date) -> Date {
        let exponent = max(0, attemptNumber - 1)
        let multiplier = pow(2.0, Double(min(exponent, 10)))
        let delay = min(baseDelaySeconds * multiplier, maximumDelaySeconds)
        return now.addingTimeInterval(delay)
    }
}
