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

    func pull(context _: SyncContext) throws -> SyncCursor? {
        nil
    }

    /// Sends every write that is still waiting, oldest first, in batches until none is left.
    ///
    /// A write that is waiting out its retry delay goes too. A run starts when the
    /// person writes something, opens the app, pulls to refresh, or the retry timer
    /// fires, so this is the moment to try. The delay only decides when the retry
    /// timer fires next. Each write is tried at most once per run.
    func push(context: SyncContext) async throws {
        let ownerUserID = context.session.userID
        // Writes the server accepted still hold what was sent, and nothing reads
        // them again. A failed cleanup must not stop the sending below.
        try? await context.pendingOperationStore.deleteCompleted(ownerUserID: ownerUserID)

        var attempted = Set<UUID>()
        var unsupportedKind: String?
        while true {
            try Task.checkCancellation()
            let operations = try await context.pendingOperationStore.readyOperations(
                ownerUserID: ownerUserID,
                limit: attempted.count + batchSize,
                now: .distantFuture
            )
            .filter { !attempted.contains($0.operation.id) }
            guard !operations.isEmpty else {
                break
            }

            for operation in operations {
                try Task.checkCancellation()
                attempted.insert(operation.operation.id)

                guard let operationKind = operation.operationKind,
                      let handler = handlers[operationKind] else {
                    // This build cannot send it. Keep it, send the writes behind
                    // it, and fail the run afterwards.
                    unsupportedKind = unsupportedKind ?? operation.operationKind?.rawValue ?? "unknown"
                    continue
                }
                try await send(operation, with: handler, context: context)
            }
        }

        if let unsupportedKind {
            throw PendingSyncOperationDrainError.unsupportedOperationKind(unsupportedKind)
        }
    }

    private func send(
        _ operation: PendingSyncOperationSnapshot,
        with handler: any PendingSyncOperationHandling,
        context: SyncContext
    ) async throws {
        let store = context.pendingOperationStore
        let operationID = operation.operation.id
        let attemptNumber = operation.attemptCount + 1

        do {
            try await store.markSending(clientOperationID: operationID, at: Date())
        } catch PendingSyncOperationClaimError.notPending {
            return
        }

        do {
            switch try await handler.send(operation, context: context) {
            case .succeeded:
                try await store.markSucceeded(clientOperationID: operationID, at: Date())
            case let .retry(nextRetryAt):
                try await recordRetryOrTerminalFailure(
                    operation: operation,
                    attemptNumber: attemptNumber,
                    errorDescription: "Retry later",
                    nextRetryAt: nextRetryAt,
                    context: context
                )
            case let .terminalFailure(errorDescription):
                try await store.markTerminalFailure(
                    clientOperationID: operationID,
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
        // Retries only run while the app is open. Five minutes keeps a write made
        // offline from waiting long after the connection comes back.
        maximumDelaySeconds: TimeInterval = 300
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
