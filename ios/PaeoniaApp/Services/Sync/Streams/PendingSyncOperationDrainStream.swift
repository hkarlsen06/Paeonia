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

    /// The drain saved that `operation` succeeded, so it is never sent again. Delete
    /// files that only a replay needed. Until now, a crash replays the send, which
    /// still needs them. Does nothing by default.
    func didRecordSuccess(of operation: PendingSyncOperationSnapshot) async

    /// How long one try of `operation` may run, such as longer for a send that uploads a
    /// big file (`UploadTimeLimit`). Nil, the default, uses the drain's limit.
    nonisolated func timeLimit(for operation: PendingSyncOperationSnapshot) -> Duration?

    /// The person took `operation` back after it was tried. A try that is running when
    /// this turns true stops, and the write waits for its next try, which `send` makes
    /// without starting anything new. False by default.
    func isTakenBack(_ operation: PendingSyncOperationSnapshot, context: SyncContext) async -> Bool
}

extension PendingSyncOperationHandling {
    nonisolated var showsGivenUpWrites: Bool { false }

    nonisolated func timeLimit(for _: PendingSyncOperationSnapshot) -> Duration? { nil }

    // swiftlint:disable:next async_without_await
    func isTakenBack(_: PendingSyncOperationSnapshot, context _: SyncContext) async -> Bool { false }

    // swiftlint:disable:next async_without_await
    func gaveUp(on _: PendingSyncOperationSnapshot, context _: SyncContext) async {}

    // swiftlint:disable:next async_without_await
    func didRecordSuccess(of _: PendingSyncOperationSnapshot) async {}
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

/// The person took the write back while it was sending.
private nonisolated struct OperationTakenBack: Error {}

/// How long a send that uploads files may run: five minutes, or as long as the bytes take at
/// 256 kbit/s, a slow mobile connection. An 80 MB video gets about 44 minutes.
nonisolated enum UploadTimeLimit {
    static let minimum: Duration = .seconds(300)
    static let slowestBytesPerSecond: Int64 = 32_000

    static func forUploading(_ byteCount: Int64) -> Duration {
        max(minimum, .seconds(byteCount / slowestBytesPerSecond))
    }
}

nonisolated enum PendingSyncOperationDrainError: Error, Equatable, Sendable {
    case unsupportedOperationKind(String)
}

struct PendingSyncOperationDrainStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .pendingOperations

    private let handlers: [SyncPendingOperationKind: any PendingSyncOperationHandling]
    private let batchSize: Int
    private let retryPolicy: PendingSyncOperationRetryPolicy
    private let operationTimeout: Duration
    private let foregroundStint: @Sendable () async -> Int?

    nonisolated init(
        handlers: [any PendingSyncOperationHandling],
        batchSize: Int = 25,
        retryPolicy: PendingSyncOperationRetryPolicy = PendingSyncOperationRetryPolicy(),
        // Photo and voice uploads run inside a send, so this is long, and a handler that
        // uploads more states its own. The sync run has no timeout of its own while this
        // stream drains.
        operationTimeout: Duration = UploadTimeLimit.minimum,
        foregroundStint: @escaping @Sendable () async -> Int? = { @MainActor in AppForeground.stint() }
    ) {
        self.handlers = Dictionary(uniqueKeysWithValues: handlers.map { ($0.operationKind, $0) })
        self.batchSize = batchSize
        self.retryPolicy = retryPolicy
        self.operationTimeout = operationTimeout
        self.foregroundStint = foregroundStint
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    func pull(context _: SyncContext) throws -> SyncCursor? {
        nil
    }

    /// Sends every write that is ready, oldest first, in batches until none is left.
    ///
    /// A write that is waiting out its retry delay stays put (`waitsForItsRetry`), and
    /// the retry timer starts a run when the delay ends. Each write is tried at most
    /// once per run. A write that takes longer than its time limit fails like any
    /// other, so the writes behind it still go, and gives up after
    /// `retryPolicy.maximumTimeouts` of them that ran with the app in front the whole
    /// time. When the network is down, the run stops, because every other write would
    /// only wait out its own timeout.
    func push(context: SyncContext) async throws {
        let ownerUserID = context.session.userID
        // Writes the server accepted still hold what was sent, and nothing reads
        // them again. A failed cleanup must not stop the sending below.
        try? await context.pendingOperationStore.deleteCompleted(ownerUserID: ownerUserID)

        var seen = Set<UUID>()
        var unsupportedKind: String?
        var isNetworkDown = false
        while !isNetworkDown {
            try Task.checkCancellation()
            let now = Date()
            let operations = try await context.pendingOperationStore.readyOperations(
                ownerUserID: ownerUserID,
                limit: seen.count + batchSize,
                // The store leaves out every write that waits for its retry date, which
                // suits a run for a new write or the retry timer. Other runs read them all,
                // and `waitsForItsRetry` decides.
                now: context.reason == .localChange ? now : .distantFuture
            )
            .filter { seen.insert($0.operation.id).inserted }
            guard !operations.isEmpty else {
                break
            }

            for operation in operations where !operation.waitsForItsRetry(in: context.reason, at: now) {
                try Task.checkCancellation()

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
        let stint = await foregroundStint()

        do {
            let result = try await Self.sendWithinLimit(
                operation,
                with: handler,
                context: context,
                within: handler.timeLimit(for: operation) ?? operationTimeout
            )
            try await record(result, for: operation, attemptNumber: attemptNumber, handler: handler, context: context)
        } catch let error as CancellationError {
            throw error
        } catch is OperationTakenBack {
            // The next try only finds out whether the server has it, so it may go at once.
            try await store.markRetryableFailure(
                clientOperationID: operationID,
                failure: .retryLater,
                nextRetryAt: Date(),
                at: Date()
            )
        } catch is PendingSyncOperationPayloadError {
            await handler.gaveUp(on: operation, context: context)
            try await store.markTerminalFailure(
                clientOperationID: operationID,
                errorDescription: "The saved data could not be read",
                at: Date()
            )
        } catch {
            try await recordFailedTry(error, of: operation, startedIn: stint, handler: handler, context: context)
            return Self.isNetworkDown(error)
        }
        return false
    }

    private func recordFailedTry(
        _ error: any Error,
        of operation: PendingSyncOperationSnapshot,
        startedIn stint: Int?,
        handler: any PendingSyncOperationHandling,
        context: SyncContext
    ) async throws {
        let timedOut = error is OperationDeadlineExceeded
        // The time limit's clock runs on while iOS pauses the app in the background, so a
        // try the person left the app during may have had little time to send.
        let timedOutInFront = if timedOut, let stint { await foregroundStint() == stint } else { false }
        var failure = PendingSyncFailure(error)
        failure.timedOut = timedOutInFront
        try await recordRetryOrTerminalFailure(
            operation: operation,
            attemptNumber: operation.attemptCount + 1,
            failure: failure,
            nextRetryAt: nil,
            // A write that waits for a connection is safe on the phone, however long it waits.
            // A send that keeps running out of time with the app in front on a working
            // connection will not get through, so it gives up after a few tries and shows
            // as not sent.
            mayGiveUp: timedOut
                ? timedOutInFront && retryPolicy.hasTimedOutTooOften(operation.timedOutAttempts + 1)
                : !Self.isNetworkDown(error) && !Self.isWeakConnection(error),
            ignoresAge: timedOut,
            handler: handler,
            context: context
        )
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
            await handler.didRecordSuccess(of: operation)
            // The server has the change, so the Lock Screen widgets can fetch it.
            if operation.operationKind?.changesLockScreenWidgets == true {
                LockScreenWidgetReloader.reloadIfNotActive()
            }
        case let .retry(nextRetryAt):
            try await recordRetryOrTerminalFailure(
                operation: operation,
                attemptNumber: attemptNumber,
                failure: .retryLater,
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

    /// Cancels the send once `limit` passes and throws `OperationDeadlineExceeded`, or
    /// once the person takes it back and throws `OperationTakenBack`.
    private nonisolated static func sendWithinLimit(
        _ operation: PendingSyncOperationSnapshot,
        with handler: any PendingSyncOperationHandling,
        context: SyncContext,
        within limit: Duration
    ) async throws -> PendingSyncOperationSendResult {
        // Listens before asking, so a take-back between the two is not missed.
        let changes = LocalStoreChanges.changes(in: .pendingOperations)
        let wasTakenBack = await handler.isTakenBack(operation, context: context)
        return try await withThrowingTaskGroup(of: PendingSyncOperationSendResult.self) { group in
            group.addTask {
                try await handler.send(operation, context: context)
            }
            group.addTask {
                // Runs on while iOS pauses the app in the background, so `recordFailedTry`
                // counts a timeout toward giving up only when the app stayed in front.
                try await Task.sleep(for: limit, clock: .suspending)
                throw OperationDeadlineExceeded()
            }
            // A send that starts taken back makes no new upload, so it runs to its end.
            if !wasTakenBack {
                group.addTask {
                    for await change in changes where change.ownerUserID == operation.ownerUserID {
                        if await handler.isTakenBack(operation, context: context) { throw OperationTakenBack() }
                    }
                    throw CancellationError()
                }
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
        failure: PendingSyncFailure,
        nextRetryAt: Date?,
        mayGiveUp: Bool = true,
        ignoresAge: Bool = false,
        handler: any PendingSyncOperationHandling,
        context: SyncContext
    ) async throws {
        let now = Date()
        if mayGiveUp, handler.showsGivenUpWrites, ignoresAge || retryPolicy.shouldMarkTerminal(
            attemptNumber: attemptNumber,
            createdAt: operation.operation.localCreatedAt,
            now: now
        ) {
            await handler.gaveUp(on: operation, context: context)
            try await context.pendingOperationStore.markTerminalFailure(
                clientOperationID: operation.operation.id,
                errorDescription: failure.description,
                at: now
            )
            return
        }

        try await context.pendingOperationStore.markRetryableFailure(
            clientOperationID: operation.operation.id,
            failure: failure,
            nextRetryAt: nextRetryAt ?? retryPolicy.nextRetryDate(
                attemptNumber: attemptNumber,
                now: now
            ),
            at: now
        )
    }
}

private extension PendingSyncOperationSnapshot {
    /// Whether this write sits out a run for `reason` to wait for its retry date. A pull to
    /// refresh tries every write. A run at launch, on coming back to the app or when the
    /// connection comes back also tries a write that failed only because the phone had no
    /// connection, so it goes as soon as the phone is online again. Its retry date still
    /// paces the retry timer, so a phone that stays offline does not try in a loop, and a
    /// run for a new write tries that new write first. A write that failed another way,
    /// such as a server error, waits out its delay, so a failing server is not asked again
    /// and again.
    nonisolated func waitsForItsRetry(in reason: SyncRequestReason, at now: Date) -> Bool {
        guard reason != .manualRefresh,
              status == .failedRetryable,
              lastFailureKind != .offline || reason == .localChange,
              let nextRetryAt
        else {
            return false
        }
        return nextRetryAt > now
    }
}

nonisolated struct PendingSyncOperationRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int?
    /// A write older than this stops retrying after a failure that is not a lost
    /// connection, and shows as not sent.
    let maximumAgeSeconds: TimeInterval?
    let baseDelaySeconds: TimeInterval
    let maximumDelaySeconds: TimeInterval
    /// A write that ran out of its time limit this many times with the app in front shows as
    /// not sent. The limit already allows a slow connection, so trying more only spends data
    /// again.
    let maximumTimeouts: Int

    init(
        maximumAttempts: Int? = nil,
        maximumAgeSeconds: TimeInterval? = 24 * 60 * 60,
        baseDelaySeconds: TimeInterval = 60,
        // Retries only run while the app is open. Five minutes keeps a write made
        // offline from waiting long after the connection comes back.
        maximumDelaySeconds: TimeInterval = 300,
        maximumTimeouts: Int = 3
    ) {
        self.maximumAttempts = maximumAttempts
        self.maximumAgeSeconds = maximumAgeSeconds
        self.baseDelaySeconds = baseDelaySeconds
        self.maximumDelaySeconds = maximumDelaySeconds
        self.maximumTimeouts = maximumTimeouts
    }

    func hasTimedOutTooOften(_ timeouts: Int) -> Bool {
        timeouts >= maximumTimeouts
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
