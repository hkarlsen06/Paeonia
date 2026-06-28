import Foundation
import Testing
@testable import PaeoniaApp

struct PaeoniaSyncServiceTests {
    @Test func runOncePullsBeforePushingEachStream() async {
        let relationshipStream = RecordingSyncStream(streamKey: .relationship)
        let profileStream = RecordingSyncStream(streamKey: .profile)
        let stateStore = InMemorySyncStateRepository()
        let coordinator = PaeoniaSyncService(
            streams: [relationshipStream, profileStream],
            stateStore: stateStore,
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        await coordinator.configure(session: .test())

        let result = await coordinator.runOnce(reason: .manualRefresh)

        #expect(result.status == .succeeded)
        #expect(result.attemptedStreamCount == 2)
        #expect(result.completedStreamCount == 2)
        #expect(await relationshipStream.events == [
            "relationship.pull.manual_refresh",
            "relationship.push.manual_refresh"
        ])
        #expect(await profileStream.events == [
            "profile.pull.manual_refresh",
            "profile.push.manual_refresh"
        ])
        let states = try? await stateStore.snapshots(ownerUserID: .testUserID)
        #expect(states?.map(\.streamKey) == [.profile, .relationship])
    }

    @Test func runOnceDrainsCoalescedFollowUpBeforeReturning() async {
        let relationshipStream = BlockingFirstPullSyncStream(streamKey: .relationship)
        let coordinator = PaeoniaSyncService(
            streams: [relationshipStream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        await coordinator.configure(session: .test())

        let firstRun = Task {
            await coordinator.runOnce(reason: .manualRefresh)
        }
        await relationshipStream.waitForFirstPull()

        let coalescedProbe = AsyncCompletionProbe()
        let coalescedRun = Task {
            let result = await coordinator.runOnce(reason: .localChange)
            await coalescedProbe.markCompleted()
            return result
        }
        for _ in 0..<1_000 {
            if await coalescedProbe.isCompleted {
                break
            }
            await Task.yield()
        }
        let completedBeforeRelease = await coalescedProbe.isCompleted
        #expect(!completedBeforeRelease)

        await relationshipStream.releaseFirstPull()
        let coalescedResult = await coalescedRun.value
        let result = await firstRun.value

        #expect(coalescedResult.status == .coalesced)
        #expect(result.status == .succeeded)
        #expect(await relationshipStream.events == [
            "relationship.pull.manual_refresh",
            "relationship.push.manual_refresh",
            "relationship.pull.local_change",
            "relationship.push.local_change",
        ])
    }

    @Test func scheduledStartupDrainsImmediateCoalescedFollowUpBeforeReturning() async {
        let relationshipStream = BlockingFirstPullSyncStream(streamKey: .relationship)
        let coordinator = PaeoniaSyncService(
            streams: [relationshipStream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        await coordinator.configure(session: .test())

        await coordinator.start()
        let coalescedProbe = AsyncCompletionProbe()
        let coalescedRun = Task {
            let result = await coordinator.runOnce(reason: .manualRefresh)
            await coalescedProbe.markCompleted()
            return result
        }

        await relationshipStream.waitForFirstPull()
        for _ in 0..<1_000 {
            if await coalescedProbe.isCompleted {
                break
            }
            await Task.yield()
        }
        let completedBeforeRelease = await coalescedProbe.isCompleted
        #expect(!completedBeforeRelease)

        await relationshipStream.releaseFirstPull()
        let coalescedResult = await coalescedRun.value

        #expect(coalescedResult.status == .coalesced)
        #expect(await relationshipStream.events == [
            "relationship.pull.startup",
            "relationship.push.startup",
            "relationship.pull.local_change",
            "relationship.push.local_change",
        ])
    }

    @Test func runOnceSchedulesPendingOperationRetry() async throws {
        let ownerUserID = UUID.testUserID
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:\(operation.id)"
            )
        )
        let handler = RetryThenSucceedPendingOperationHandler(operationKind: .submitDailyAnswer)
        let stream = PendingSyncOperationDrainStream(
            handlers: [handler],
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )
        let coordinator = PaeoniaSyncService(
            streams: [stream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )
        await coordinator.configure(session: .test())

        let result = await coordinator.runOnce(reason: .localChange)
        await handler.waitForSendCount(2)

        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date()
        )
        #expect(result.status == .succeeded)
        #expect(readyOperations.isEmpty)
    }

    @Test func failedRunSchedulesRetry() async {
        let stream = FailOnceSyncStream(streamKey: .relationship)
        let coordinator = PaeoniaSyncService(
            streams: [stream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            failedRunRetryDelay: 0
        )
        await coordinator.configure(session: .test())

        let result = await coordinator.runOnce(reason: .localChange)
        await stream.waitForPullCount(2)

        #expect(result.status == .failed)
        #expect(await stream.events == [
            "relationship.pull.local_change",
            "relationship.pull.local_change",
            "relationship.push.local_change",
        ])
    }

    @Test func failedStreamStopsRunBeforeLaterStreams() async {
        let relationshipStream = RecordingSyncStream(
            streamKey: .relationship,
            failure: .pull
        )
        let profileStream = RecordingSyncStream(streamKey: .profile)
        let stateStore = InMemorySyncStateRepository()
        let coordinator = PaeoniaSyncService(
            streams: [relationshipStream, profileStream],
            stateStore: stateStore,
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            minimumForegroundSyncInterval: 0
        )
        await coordinator.configure(session: .test())

        let result = await coordinator.runOnce(reason: .foreground)

        #expect(result.status == .failed)
        #expect(result.failedStreamKey == .relationship)
        #expect(result.completedStreamCount == 0)
        #expect(await relationshipStream.events == [
            "relationship.pull.foreground"
        ])
        #expect(await profileStream.events == [])
        let states = try? await stateStore.snapshots(ownerUserID: .testUserID)
        #expect(states?.first?.lastSyncError != nil)
    }

    @Test func runOnceWithoutSessionSkips() async {
        let coordinator = PaeoniaSyncService(
            streams: [RecordingSyncStream(streamKey: .relationship)],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let result = await coordinator.runOnce(reason: .manualRefresh)

        #expect(result.status == .skippedNoSession)
        #expect(result.attemptedStreamCount == 0)
    }

    @Test func startupRunRetriesOperationsLeftSendingByPreviousLaunch() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let operation = SyncClientOperation(
            id: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientID: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientSequence: 1,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )

        try await pendingStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: .testUserID,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily-answer:test"
            )
        )
        try await pendingStore.markSending(
            clientOperationID: operation.id,
            at: Date(timeIntervalSince1970: 200)
        )

        let coordinator = PaeoniaSyncService(
            streams: [RecordingSyncStream(streamKey: .relationship)],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pendingStore
        )
        await coordinator.configure(session: .test())

        let result = await coordinator.runOnce(reason: .startup)
        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: .testUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 300)
        )

        #expect(result.status == .succeeded)
        #expect(readyOperations.map(\.operation.id) == [operation.id])
        #expect(readyOperations.first?.status == .retrying)
    }
}

private actor AsyncCompletionProbe {
    private var completed = false

    var isCompleted: Bool {
        completed
    }

    func markCompleted() {
        completed = true
    }
}

private enum RecordingSyncStreamFailure: Sendable {
    case pull
    case push
}

private enum RecordingSyncStreamError: Error {
    case requestedFailure
}

private actor BlockingFirstPullSyncStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey
    private var recordedEvents: [String] = []
    private var firstPullStarted = false
    private var firstPullStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstPullReleaseContinuation: CheckedContinuation<Void, Never>?

    init(streamKey: SyncStreamKey) {
        self.streamKey = streamKey
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    var events: [String] {
        recordedEvents
    }

    func waitForFirstPull() async {
        if firstPullStarted {
            return
        }

        await withCheckedContinuation { continuation in
            firstPullStartedContinuation = continuation
        }
    }

    func releaseFirstPull() {
        firstPullReleaseContinuation?.resume()
        firstPullReleaseContinuation = nil
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        recordedEvents.append("\(streamKey.rawValue).pull.\(context.reason.rawValue)")

        if !firstPullStarted {
            firstPullStarted = true
            firstPullStartedContinuation?.resume()
            firstPullStartedContinuation = nil

            await withCheckedContinuation { continuation in
                firstPullReleaseContinuation = continuation
            }
        }

        return SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 100),
            tieID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
    }

    func push(context: SyncContext) async throws {
        recordedEvents.append("\(streamKey.rawValue).push.\(context.reason.rawValue)")
    }
}

private actor FailOnceSyncStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey
    private var recordedEvents: [String] = []
    private var pullCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(streamKey: SyncStreamKey) {
        self.streamKey = streamKey
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    var events: [String] {
        recordedEvents
    }

    func waitForPullCount(_ expectedCount: Int) async {
        if pullCount >= expectedCount {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        pullCount += 1
        recordedEvents.append("\(streamKey.rawValue).pull.\(context.reason.rawValue)")
        waiters.forEach { $0.resume() }
        waiters.removeAll()

        if pullCount == 1 {
            throw RecordingSyncStreamError.requestedFailure
        }

        return SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 100),
            tieID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
    }

    func push(context: SyncContext) async throws {
        recordedEvents.append("\(streamKey.rawValue).push.\(context.reason.rawValue)")
    }
}

private actor RecordingSyncStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey
    private let failure: RecordingSyncStreamFailure?
    private var recordedEvents: [String] = []

    init(streamKey: SyncStreamKey, failure: RecordingSyncStreamFailure? = nil) {
        self.streamKey = streamKey
        self.failure = failure
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    var events: [String] {
        recordedEvents
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        recordedEvents.append("\(streamKey.rawValue).pull.\(context.reason.rawValue)")

        if failure == .pull {
            throw RecordingSyncStreamError.requestedFailure
        }

        return SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 100),
            tieID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
    }

    func push(context: SyncContext) async throws {
        recordedEvents.append("\(streamKey.rawValue).push.\(context.reason.rawValue)")

        if failure == .push {
            throw RecordingSyncStreamError.requestedFailure
        }
    }
}

private actor RetryThenSucceedPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind
    private var sendCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(operationKind: SyncPendingOperationKind) {
        self.operationKind = operationKind
    }

    func waitForSendCount(_ expectedCount: Int) async {
        if sendCount >= expectedCount {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        sendCount += 1
        waiters.forEach { $0.resume() }
        waiters.removeAll()

        if sendCount == 1 {
            throw RecordingSyncStreamError.requestedFailure
        }

        return .succeeded
    }
}

private extension SyncSession {
    static func test() -> SyncSession {
        SyncSession(userID: .testUserID)
    }
}

private extension UUID {
    static let testUserID: UUID = {
        guard let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111") else {
            preconditionFailure("Invalid test UUID")
        }

        return id
    }()
}
