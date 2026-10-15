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

    @Test func scheduledStartupSkipsFollowUpForCoalescedForegroundRefresh() async {
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
            // A foreground-ish refresh that coalesces onto the in-flight startup
            // run must not queue a second full pipeline pass — the in-flight run
            // already refreshes every read stream.
            let result = await coordinator.runOnce(reason: .foreground)
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

/// Sign-out sends what it can before the purge and never waits long for it.
struct PaeoniaSyncServiceSignOutFlushTests {
    @Test func flushSendsAWaitingWrite() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(Self.request())
        let handler = HangingPendingOperationHandler(hangs: false)
        let service = Self.makeService(handler: handler, store: pendingStore)
        await service.configure(session: .test())

        await service.flushPendingWrites(timeout: .seconds(5))

        #expect(await handler.sendCount == 1)
        let waiting = try await pendingStore.readyOperations(
            ownerUserID: .testUserID,
            limit: 10,
            now: .distantFuture
        )
        #expect(waiting.isEmpty)
    }

    @Test func flushStopsWaitingAtItsTimeoutAndSignOutStillFinishes() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(Self.request())
        let handler = HangingPendingOperationHandler(hangs: true)
        let service = Self.makeService(handler: handler, store: pendingStore)
        await service.configure(session: .test())

        let started = ContinuousClock.now
        await service.flushPendingWrites(timeout: .milliseconds(200))

        // The stuck send waits 60 s, so returning well before that proves the cap
        // worked. The margin leaves room for a busy test machine.
        #expect(ContinuousClock.now - started < .seconds(30))
        #expect(await waitUntil { await handler.sendCount == 1 })
        // The purge step cancels the stuck send instead of waiting for it.
        await service.resetForUserChange()
    }

    @Test func flushWithoutASessionSendsNothing() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await pendingStore.enqueue(Self.request())
        let handler = HangingPendingOperationHandler(hangs: false)
        let service = Self.makeService(handler: handler, store: pendingStore)

        await service.flushPendingWrites(timeout: .seconds(1))

        #expect(await handler.sendCount == 0)
    }

    private static func makeService(
        handler: HangingPendingOperationHandler,
        store: InMemoryPendingSyncOperationRepository
    ) -> PaeoniaSyncService {
        PaeoniaSyncService(
            streams: [PendingSyncOperationDrainStream(handlers: [handler])],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: store
        )
    }

    private static func request() -> PendingSyncOperationRequest {
        PendingSyncOperationRequest(
            ownerUserID: .testUserID,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
            operationKind: .submitDailyAnswer,
            idempotencyScope: "flush-test"
        )
    }
}

/// Records each send. When `hangs` is true, a send waits until it is cancelled.
private actor HangingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitDailyAnswer
    private let hangs: Bool
    private(set) var sendCount = 0

    init(hangs: Bool) {
        self.hangs = hangs
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        sendCount += 1
        if hangs {
            try await Task.sleep(for: .seconds(60))
        }
        return .succeeded
    }
}
