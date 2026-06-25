import Foundation

nonisolated protocol SyncCoordinating: Actor {
    func configure(session: SyncSession?)
    func start()
    func requestSync(reason: SyncRequestReason)
    func stop()
    func resetForUserChange()
}

nonisolated protocol SyncStream: Sendable {
    var streamKey: SyncStreamKey { get }

    func scope(for session: SyncSession) -> SyncStreamScope?
    func pull(context: SyncContext) async throws -> SyncCursor?
    func push(context: SyncContext) async throws
}

nonisolated struct SyncSession: Equatable, Sendable {
    let userID: UUID
    let activeCoupleID: UUID?

    init(userID: UUID, activeCoupleID: UUID? = nil) {
        self.userID = userID
        self.activeCoupleID = activeCoupleID
    }

    init?(authSession: AuthSession, activeCoupleID: UUID? = nil) {
        guard let userID = UUID(uuidString: authSession.id) else {
            return nil
        }

        self.init(userID: userID, activeCoupleID: activeCoupleID)
    }
}

nonisolated struct SyncContext: Sendable {
    let session: SyncSession
    let reason: SyncRequestReason
    let startedAt: Date
    let streamCursor: SyncCursor
    let stateStore: any SyncStatePersisting
    let pendingOperationStore: any PendingSyncOperationPersisting

    init(
        session: SyncSession,
        reason: SyncRequestReason,
        startedAt: Date = Date(),
        streamCursor: SyncCursor = SyncCursor(),
        stateStore: any SyncStatePersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.session = session
        self.reason = reason
        self.startedAt = startedAt
        self.streamCursor = streamCursor
        self.stateStore = stateStore
        self.pendingOperationStore = pendingOperationStore
    }
}

nonisolated enum SyncRunStatus: Equatable, Sendable {
    case succeeded
    case failed
    case coalesced
    case skippedNoSession
    case skippedInterval
    case cancelled
    case timedOut
}

nonisolated struct SyncRunResult: Equatable, Sendable {
    let status: SyncRunStatus
    let attemptedStreamCount: Int
    let completedStreamCount: Int
    let failedStreamKey: SyncStreamKey?
    let errorDescription: String?

    static func coalesced() -> SyncRunResult {
        SyncRunResult(
            status: .coalesced,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    static func skippedNoSession() -> SyncRunResult {
        SyncRunResult(
            status: .skippedNoSession,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    static func skippedInterval() -> SyncRunResult {
        SyncRunResult(
            status: .skippedInterval,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    static func timedOut() -> SyncRunResult {
        SyncRunResult(
            status: .timedOut,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: "Sync timed out"
        )
    }
}

actor SyncCoordinator: SyncCoordinating {
    private let streams: [any SyncStream]
    private let stateStore: any SyncStatePersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let minimumForegroundSyncInterval: TimeInterval
    private let syncTimeoutNanoseconds: UInt64

    private var session: SyncSession?
    private var hasStarted = false
    private var isSyncing = false
    private var needsFollowUpSync = false
    private var scheduledTask: Task<Void, Never>?
    private var scheduleGeneration: UInt64 = 0
    private var lastForegroundSyncAt: Date?

    init(
        streams: [any SyncStream] = [],
        stateStore: (any SyncStatePersisting)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        accessSnapshotStore: (any AccessSyncSnapshotPersisting)? = nil,
        relationshipEventStore: (any RelationshipSyncEventPersisting)? = nil,
        pendingOperationHandlers: [any PendingSyncOperationHandling] = [],
        minimumForegroundSyncInterval: TimeInterval = 60,
        syncTimeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        let needsDefaultStreamStores = streams.isEmpty
            && (accessSnapshotStore == nil || relationshipEventStore == nil)
        let needsDefaultStores = stateStore == nil
            || pendingOperationStore == nil
            || needsDefaultStreamStores
        let fallbackStores = needsDefaultStores ? Self.makeDefaultStores() : nil
        if streams.isEmpty {
            guard let resolvedAccessSnapshotStore = accessSnapshotStore ?? fallbackStores?.accessSnapshotStore,
                let resolvedRelationshipEventStore = relationshipEventStore ?? fallbackStores?.relationshipEventStore else {
                preconditionFailure("Default sync streams require persistent sync stores")
            }

            self.streams = Self.makeDefaultStreams(
                accessSnapshotStore: resolvedAccessSnapshotStore,
                relationshipEventStore: resolvedRelationshipEventStore,
                pendingOperationHandlers: pendingOperationHandlers
            )
        } else {
            self.streams = streams
        }

        guard let resolvedStateStore = stateStore ?? fallbackStores?.stateStore,
            let resolvedPendingOperationStore = pendingOperationStore ?? fallbackStores?.pendingOperationStore else {
            preconditionFailure("SyncCoordinator requires sync state and pending operation stores")
        }

        self.stateStore = resolvedStateStore
        self.pendingOperationStore = resolvedPendingOperationStore
        self.minimumForegroundSyncInterval = minimumForegroundSyncInterval
        self.syncTimeoutNanoseconds = syncTimeoutNanoseconds
    }

    func configure(session: SyncSession?) {
        let previousUserID = self.session?.userID
        self.session = session

        if previousUserID != nil, previousUserID != session?.userID {
            scheduleGeneration &+= 1
            scheduledTask?.cancel()
            scheduledTask = nil
            isSyncing = false
            needsFollowUpSync = false
            lastForegroundSyncAt = nil
        }

        if hasStarted, session != nil {
            scheduleSync(reason: .startup)
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true

        if session != nil {
            scheduleSync(reason: .startup)
        }
    }

    func requestSync(reason: SyncRequestReason) {
        hasStarted = true

        guard session != nil else {
            return
        }

        scheduleSync(reason: reason)
    }

    func stop() {
        scheduleGeneration &+= 1
        scheduledTask?.cancel()
        scheduledTask = nil
        hasStarted = false
        isSyncing = false
        needsFollowUpSync = false
    }

    func resetForUserChange() {
        let oldUserID = session?.userID
        stop()
        session = nil
        lastForegroundSyncAt = nil

        if let oldUserID {
            Task {
                try? await pendingOperationStore.resetInFlight(ownerUserID: oldUserID)
            }
        }
    }

    func runOnce(reason: SyncRequestReason) async -> SyncRunResult {
        guard !isSyncing else {
            needsFollowUpSync = true
            return .coalesced()
        }

        guard let session else {
            return .skippedNoSession()
        }

        if shouldSkipForInterval(reason: reason, now: Date()) {
            return .skippedInterval()
        }

        hasStarted = true
        isSyncing = true
        defer { isSyncing = false }

        return await performRunWithTimeout(reason: reason, session: session)
    }

    private static func makeDefaultStores() -> (
        stateStore: any SyncStatePersisting,
        pendingOperationStore: any PendingSyncOperationPersisting,
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        relationshipEventStore: any RelationshipSyncEventPersisting
    ) {
        do {
            let localStore = try PaeoniaLocalStore()
            return (
                SwiftDataSyncStateRepository(container: localStore.container),
                SwiftDataPendingSyncOperationRepository(container: localStore.container),
                SwiftDataAccessSyncSnapshotRepository(container: localStore.container),
                SwiftDataRelationshipSyncEventRepository(container: localStore.container)
            )
        } catch {
            preconditionFailure("Unable to create persistent sync store: \(error)")
        }
    }

    private static func makeDefaultStreams(
        accessSnapshotStore: any AccessSyncSnapshotPersisting,
        relationshipEventStore: any RelationshipSyncEventPersisting,
        pendingOperationHandlers: [any PendingSyncOperationHandling] = []
    ) -> [any SyncStream] {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return []
        }

        let gateway = LiveSupabaseAccessGateway(client: client)
        return [
            AccessSyncStream(
                gateway: gateway,
                snapshotStore: accessSnapshotStore
            ),
            RelationshipSyncEventsStream(
                gateway: gateway,
                eventStore: relationshipEventStore
            ),
            PendingSyncOperationDrainStream(
                handlers: pendingOperationHandlers
            )
        ]
    }

    private func scheduleSync(reason: SyncRequestReason) {
        guard !isSyncing else {
            needsFollowUpSync = true
            return
        }

        guard session != nil else {
            return
        }

        isSyncing = true
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        scheduledTask?.cancel()
        scheduledTask = Task {
            await drainScheduledSync(reason: reason, generation: generation)
        }
    }

    private func drainScheduledSync(reason: SyncRequestReason, generation: UInt64) async {
        var nextReason = reason

        while true {
            guard let session else {
                finishScheduledSync(generation: generation)
                return
            }

            needsFollowUpSync = false

            if shouldSkipForInterval(reason: nextReason, now: Date()) {
                finishScheduledSync(generation: generation)
                return
            }

            _ = await performRunWithTimeout(reason: nextReason, session: session)

            if Task.isCancelled {
                finishScheduledSync(generation: generation)
                return
            }

            if needsFollowUpSync {
                nextReason = .localChange
            } else {
                finishScheduledSync(generation: generation)
                return
            }
        }
    }

    private func finishScheduledSync(generation: UInt64) {
        guard generation == scheduleGeneration else {
            return
        }

        isSyncing = false
        scheduledTask = nil
    }

    private func shouldSkipForInterval(reason: SyncRequestReason, now: Date) -> Bool {
        guard reason == .foreground else {
            return false
        }

        if let lastForegroundSyncAt,
           now.timeIntervalSince(lastForegroundSyncAt) < minimumForegroundSyncInterval {
            return true
        }

        lastForegroundSyncAt = now
        return false
    }

    private func performRunWithTimeout(
        reason: SyncRequestReason,
        session: SyncSession
    ) async -> SyncRunResult {
        let timeoutNanoseconds = syncTimeoutNanoseconds
        let stream = AsyncStream<SyncRunResult> { continuation in
            let runTask = Task {
                let result = await performRun(reason: reason, session: session)
                continuation.yield(result)
                continuation.finish()
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                runTask.cancel()
                continuation.yield(.timedOut())
                continuation.finish()
            }

            continuation.onTermination = { _ in
                runTask.cancel()
                timeoutTask.cancel()
            }
        }

        for await result in stream {
            return result
        }

        return SyncRunResult(
            status: .cancelled,
            attemptedStreamCount: 0,
            completedStreamCount: 0,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }

    private func performRun(
        reason: SyncRequestReason,
        session: SyncSession
    ) async -> SyncRunResult {
        let startedAt = Date()
        var attemptedStreamCount = 0
        var completedStreamCount = 0

        try? await pendingOperationStore.resetInFlight(ownerUserID: session.userID)

        for stream in streams {
            if Task.isCancelled {
                return SyncRunResult(
                    status: .cancelled,
                    attemptedStreamCount: attemptedStreamCount,
                    completedStreamCount: completedStreamCount,
                    failedStreamKey: nil,
                    errorDescription: nil
                )
            }

            let streamKey = stream.streamKey

            guard let scope = stream.scope(for: session) else {
                continue
            }

            attemptedStreamCount += 1

            do {
                let cursor = try await stateStore.cursor(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey
                )
                let context = SyncContext(
                    session: session,
                    reason: reason,
                    startedAt: startedAt,
                    streamCursor: cursor,
                    stateStore: stateStore,
                    pendingOperationStore: pendingOperationStore
                )

                try await stateStore.markAttempted(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey,
                    at: startedAt
                )
                let nextCursor = try await stream.pull(context: context)
                try Task.checkCancellation()
                try await stream.push(context: context)
                try Task.checkCancellation()
                try await stateStore.markSucceeded(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey,
                    cursor: nextCursor,
                    at: Date()
                )
                completedStreamCount += 1
            } catch is CancellationError {
                return SyncRunResult(
                    status: .cancelled,
                    attemptedStreamCount: attemptedStreamCount,
                    completedStreamCount: completedStreamCount,
                    failedStreamKey: streamKey,
                    errorDescription: nil
                )
            } catch {
                let errorDescription = String(describing: error)
                try? await stateStore.markFailed(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: streamKey,
                    errorDescription: errorDescription,
                    at: Date()
                )

                return SyncRunResult(
                    status: .failed,
                    attemptedStreamCount: attemptedStreamCount,
                    completedStreamCount: completedStreamCount,
                    failedStreamKey: streamKey,
                    errorDescription: errorDescription
                )
            }
        }

        return SyncRunResult(
            status: .succeeded,
            attemptedStreamCount: attemptedStreamCount,
            completedStreamCount: completedStreamCount,
            failedStreamKey: nil,
            errorDescription: nil
        )
    }
}
