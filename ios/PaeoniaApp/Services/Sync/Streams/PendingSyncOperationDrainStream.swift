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

    /// True when `gaveUp` puts the content back or shows it as not sent. Only then may
    /// the drain stop retrying an old write. A handler without that keeps retrying,
    /// because ending its write would drop the person's content without a word.
    nonisolated var showsGivenUpWrites: Bool { get }

    /// The drain stopped retrying `operation`, and marks it failed after this
    /// returns. Show the person that it did not send, in the place where the
    /// feature shows a refused write. Does nothing by default.
    func gaveUp(on operation: PendingSyncOperationSnapshot, context: SyncContext) async
}

extension PendingSyncOperationHandling {
    nonisolated var showsGivenUpWrites: Bool { false }

    // swiftlint:disable:next async_without_await
    func gaveUp(on _: PendingSyncOperationSnapshot, context _: SyncContext) async {}
}

/// Thrown when the saved payload of a queued write is missing or cannot be read.
/// Sending again cannot fix it, so the drain marks the write failed.
nonisolated struct PendingSyncOperationPayloadError: Error, Equatable, Sendable {}

extension JSONDecoder {
    /// Reads the payload a queued write was saved with. Throws
    /// `PendingSyncOperationPayloadError` when it cannot be read, so the drain
    /// does not retry it forever.
    nonisolated func decodeQueuedPayload<Payload: Decodable>(
        _ type: Payload.Type,
        from data: Data
    ) throws -> Payload {
        do {
            return try decode(type, from: data)
        } catch {
            throw PendingSyncOperationPayloadError()
        }
    }
}

/// A send ran past its limit. It retries like any failed send, but unlike a lost
/// connection it does not stop the run, so the writes behind it still go.
private nonisolated struct OperationDeadlineExceeded: Error {}

nonisolated enum PendingSyncOperationDrainError: Error, Equatable, Sendable {
    case unsupportedOperationKind(String)
}

struct PendingSyncOperationDrainStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .pendingOperations

    private let handlers: [SyncPendingOperationKind: any PendingSyncOperationHandling]
    private let batchSize: Int
    private let retryPolicy: PendingSyncOperationRetryPolicy
    private let operationTimeout: Duration

    nonisolated init(
        handlers: [any PendingSyncOperationHandling],
        batchSize: Int = 25,
        retryPolicy: PendingSyncOperationRetryPolicy = PendingSyncOperationRetryPolicy(),
        // Photo and voice uploads run inside a send, so this is long. The sync run
        // has no timeout of its own while this stream drains.
        operationTimeout: Duration = .seconds(300)
    ) {
        self.handlers = Dictionary(uniqueKeysWithValues: handlers.map { ($0.operationKind, $0) })
        self.batchSize = batchSize
        self.retryPolicy = retryPolicy
        self.operationTimeout = operationTimeout
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    func pull(context _: SyncContext) throws -> SyncCursor? {
        nil
    }

    /// Sends every write that is ready, oldest first, in batches until none is left.
    ///
    /// A write that is waiting out its retry delay stays put, except on a pull to
    /// refresh, which tries everything. The retry timer starts a run when the delay
    /// ends. Each write is tried at most once per run. A write that takes longer
    /// than `operationTimeout` fails like any other, so the writes behind it still
    /// go. When the network is down, the run stops, because every other write
    /// would only wait out its own timeout.
    func push(context: SyncContext) async throws {
        let ownerUserID = context.session.userID
        // Writes the server accepted still hold what was sent, and nothing reads
        // them again. A failed cleanup must not stop the sending below.
        try? await context.pendingOperationStore.deleteCompleted(ownerUserID: ownerUserID)

        var attempted = Set<UUID>()
        var unsupportedKind: String?
        var isNetworkDown = false
        while !isNetworkDown {
            try Task.checkCancellation()
            let operations = try await context.pendingOperationStore.readyOperations(
                ownerUserID: ownerUserID,
                limit: attempted.count + batchSize,
                now: context.reason == .manualRefresh ? .distantFuture : Date()
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
                isNetworkDown = try await send(operation, with: handler, context: context)
                if isNetworkDown {
                    break
                }
            }
        }

        if let unsupportedKind {
            throw PendingSyncOperationDrainError.unsupportedOperationKind(unsupportedKind)
        }
    }

    /// Sends one write and records how it went. Returns true when it failed
    /// because the network is down.
    private func send(
        _ operation: PendingSyncOperationSnapshot,
        with handler: any PendingSyncOperationHandling,
        context: SyncContext
    ) async throws -> Bool {
        let store = context.pendingOperationStore
        let operationID = operation.operation.id
        let attemptNumber = operation.attemptCount + 1

        do {
            try await store.markSending(clientOperationID: operationID, at: Date())
        } catch PendingSyncOperationClaimError.notPending {
            return false
        }

        do {
            let result = try await Self.sendWithinLimit(
                operation,
                with: handler,
                context: context,
                within: operationTimeout
            )
            try await record(result, for: operation, attemptNumber: attemptNumber, handler: handler, context: context)
        } catch let error as CancellationError {
            throw error
        } catch is PendingSyncOperationPayloadError {
            await handler.gaveUp(on: operation, context: context)
            try await store.markTerminalFailure(
                clientOperationID: operationID,
                errorDescription: "The saved data could not be read",
                at: Date()
            )
        } catch {
            let isNetworkDown = Self.isNetworkDown(error)
            try await recordRetryOrTerminalFailure(
                operation: operation,
                attemptNumber: attemptNumber,
                errorDescription: String(describing: error),
                nextRetryAt: nil,
                // A write that waits for a connection is safe on the phone, however long it waits.
                // A slow upload that ran out of time is the same case.
                mayGiveUp: !isNetworkDown && !Self.isWeakConnection(error),
                handler: handler,
                context: context
            )
            return isNetworkDown
        }
        return false
    }

    private func record(
        _ result: PendingSyncOperationSendResult,
        for operation: PendingSyncOperationSnapshot,
        attemptNumber: Int,
        handler: any PendingSyncOperationHandling,
        context: SyncContext
    ) async throws {
        let store = context.pendingOperationStore
        switch result {
        case .succeeded:
            try await store.markSucceeded(clientOperationID: operation.operation.id, at: Date())
            // The server has the change, so the Lock Screen widgets can fetch it.
            if operation.operationKind?.changesLockScreenWidgets == true {
                LockScreenWidgetReloader.reloadIfNotActive()
            }
        case let .retry(nextRetryAt):
            try await recordRetryOrTerminalFailure(
                operation: operation,
                attemptNumber: attemptNumber,
                errorDescription: "Retry later",
                nextRetryAt: nextRetryAt,
                handler: handler,
                context: context
            )
        case let .terminalFailure(errorDescription):
            try await store.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: errorDescription,
                at: Date()
            )
        }
    }

    /// Cancels the send once `limit` passes and throws `OperationDeadlineExceeded`.
    private nonisolated static func sendWithinLimit(
        _ operation: PendingSyncOperationSnapshot,
        with handler: any PendingSyncOperationHandling,
        context: SyncContext,
        within limit: Duration
    ) async throws -> PendingSyncOperationSendResult {
        try await withThrowingTaskGroup(of: PendingSyncOperationSendResult.self) { group in
            group.addTask {
                try await handler.send(operation, context: context)
            }
            group.addTask {
                try await Task.sleep(for: limit)
                throw OperationDeadlineExceeded()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw OperationDeadlineExceeded()
            }
            return result
        }
    }

    /// Failures a better connection fixes, without the network being down.
    private nonisolated static func isWeakConnection(_ error: any Error) -> Bool {
        if error is OperationDeadlineExceeded { return true }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    private nonisolated static func isNetworkDown(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .notConnectedToInternet, .timedOut, .cannotConnectToHost, .networkConnectionLost:
            return true
        default:
            return false
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func recordRetryOrTerminalFailure(
        operation: PendingSyncOperationSnapshot,
        attemptNumber: Int,
        errorDescription: String,
        nextRetryAt: Date?,
        mayGiveUp: Bool = true,
        handler: any PendingSyncOperationHandling,
        context: SyncContext
    ) async throws {
        let now = Date()
        if mayGiveUp, handler.showsGivenUpWrites, retryPolicy.shouldMarkTerminal(
            attemptNumber: attemptNumber,
            createdAt: operation.operation.localCreatedAt,
            now: now
        ) {
            await handler.gaveUp(on: operation, context: context)
            try await context.pendingOperationStore.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: errorDescription,
                at: now
            )
            return
        }

        try await context.pendingOperationStore.markRetryableFailure(
            clientOperationID: operation.operation.id,
            errorDescription: errorDescription,
            nextRetryAt: nextRetryAt ?? retryPolicy.nextRetryDate(
                attemptNumber: attemptNumber,
                now: now
            ),
            at: now
        )
    }
}

nonisolated struct PendingSyncOperationRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int?
    /// A write older than this stops retrying after a failure that is not a lost
    /// connection, and shows as not sent.
    let maximumAgeSeconds: TimeInterval?
    let baseDelaySeconds: TimeInterval
    let maximumDelaySeconds: TimeInterval

    init(
        maximumAttempts: Int? = nil,
        maximumAgeSeconds: TimeInterval? = 24 * 60 * 60,
        baseDelaySeconds: TimeInterval = 60,
        // Retries only run while the app is open. Five minutes keeps a write made
        // offline from waiting long after the connection comes back.
        maximumDelaySeconds: TimeInterval = 300
    ) {
        self.maximumAttempts = maximumAttempts
        self.maximumAgeSeconds = maximumAgeSeconds
        self.baseDelaySeconds = baseDelaySeconds
        self.maximumDelaySeconds = maximumDelaySeconds
    }

    /// Age alone never ends a write on its first tries, so one bad response after a
    /// long time offline does not discard it.
    func shouldMarkTerminal(attemptNumber: Int, createdAt: Date, now: Date) -> Bool {
        if let maximumAttempts, attemptNumber >= maximumAttempts {
            return true
        }
        if let maximumAgeSeconds, attemptNumber > 3, now.timeIntervalSince(createdAt) >= maximumAgeSeconds {
            return true
        }
        return false
    }

    func nextRetryDate(attemptNumber: Int, now: Date) -> Date {
        let exponent = max(0, attemptNumber - 1)
        let multiplier = pow(2.0, Double(min(exponent, 10)))
        let delay = min(baseDelaySeconds * multiplier, maximumDelaySeconds)
        return now.addingTimeInterval(delay)
    }
}
