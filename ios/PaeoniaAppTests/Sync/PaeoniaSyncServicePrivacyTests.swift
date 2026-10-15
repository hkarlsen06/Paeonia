import Foundation
import Testing
@testable import PaeoniaApp

struct PaeoniaSyncServicePrivacyTests {
    @Test func privacyTransitionsUseTheExplicitOwnerAndDepartureScope() async {
        let privacyPurger = RecordingSyncPrivacyPurger()
        let coordinator = PaeoniaSyncService(
            streams: [RecordingSyncStream(streamKey: .relationship)],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            localPrivacyPurger: privacyPurger
        )
        await coordinator.configure(session: .test())

        await coordinator.purgeRelationshipAccess(
            ownerUserID: .testUserID,
            permanently: false
        )
        await coordinator.purgeRelationshipAccess(
            ownerUserID: .testUserID,
            permanently: true
        )
        await coordinator.resetForUserChange()

        #expect(
            await privacyPurger.calls == [
                SyncPrivacyPurgeCall(
                    ownerUserID: .testUserID,
                    scope: .relationshipAccessHidden
                ),
                SyncPrivacyPurgeCall(
                    ownerUserID: .testUserID,
                    scope: .relationshipContentPurged(clearAccessSnapshot: true)
                ),
                SyncPrivacyPurgeCall(ownerUserID: .testUserID, scope: .departingUser)
            ]
        )
    }

    @Test func departingPurgeWaitsForCancelledSyncWritesToSettle() async {
        let stream = BlockingFirstPullSyncStream(streamKey: .relationship)
        let privacyPurger = RecordingSyncPrivacyPurger()
        let coordinator = PaeoniaSyncService(
            streams: [stream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            localPrivacyPurger: privacyPurger
        )
        await coordinator.configure(session: .test())
        let sync = Task { await coordinator.runOnce(reason: .manualRefresh) }
        await stream.waitForFirstPull()

        let reset = Task { await coordinator.resetForUserChange() }
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await privacyPurger.calls.isEmpty)

        await stream.releaseFirstPull()
        await reset.value
        _ = await sync.value

        #expect(
            await privacyPurger.calls == [
                SyncPrivacyPurgeCall(ownerUserID: .testUserID, scope: .departingUser)
            ]
        )
    }

    @Test func relationshipPurgeWaitsForCancelledSyncWritesToSettle() async {
        let stream = BlockingFirstPullSyncStream(streamKey: .relationship)
        let privacyPurger = RecordingSyncPrivacyPurger()
        let coordinator = PaeoniaSyncService(
            streams: [stream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            localPrivacyPurger: privacyPurger
        )
        await coordinator.configure(session: .test())
        let sync = Task { await coordinator.runOnce(reason: .manualRefresh) }
        await stream.waitForFirstPull()

        let purge = Task {
            await coordinator.purgeRelationshipAccess(
                ownerUserID: .testUserID,
                permanently: true
            )
        }
        await stream.waitForCancellationCount(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await privacyPurger.calls.isEmpty)

        await stream.releaseFirstPull()
        #expect(await purge.value == .completed)
        _ = await sync.value

        #expect(
            await privacyPurger.calls == [
                SyncPrivacyPurgeCall(
                    ownerUserID: .testUserID,
                    scope: .relationshipContentPurged(clearAccessSnapshot: true)
                )
            ]
        )
    }

    @Test func sameUserCoupleChangeSettlesOldPipelineBeforeStartingNewSession() async throws {
        let oldCoupleID = try #require(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let newCoupleID = try #require(
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )
        let stream = BlockingFirstPullSyncStream(streamKey: .relationship)
        let coordinator = PaeoniaSyncService(
            streams: [stream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        await coordinator.configure(
            session: SyncSession(userID: .testUserID, activeCoupleID: oldCoupleID)
        )

        let oldRun = Task { await coordinator.runOnce(reason: .manualRefresh) }
        await stream.waitForFirstPull()

        let configuration = Task {
            await coordinator.configure(
                session: SyncSession(userID: .testUserID, activeCoupleID: newCoupleID)
            )
        }
        await stream.waitForCancellationCount(1)
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await stream.pulledCoupleIDs == [oldCoupleID])

        await stream.releaseFirstPull()
        await configuration.value
        _ = await oldRun.value
        await stream.waitForPullCount(2)

        #expect(await stream.pulledCoupleIDs == [oldCoupleID, newCoupleID])
        #expect(await stream.events == [
            "relationship.pull.manual_refresh",
            "relationship.pull.startup",
            "relationship.push.startup",
        ])
    }

    @Test func timedOutPipelineSettlesBeforeRetryCanStart() async {
        let stream = BlockingFirstPullSyncStream(streamKey: .relationship)
        let coordinator = PaeoniaSyncService(
            streams: [stream],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            syncTimeoutNanoseconds: 100_000_000,
            failedRunRetryDelay: 0
        )
        await coordinator.configure(session: .test())

        let timedRun = Task { await coordinator.runOnce(reason: .manualRefresh) }
        await stream.waitForFirstPull()
        await stream.waitForCancellationCount(1)

        let coalescedRun = Task { await coordinator.runOnce(reason: .manualRefresh) }
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await stream.pullCount == 1)

        await stream.releaseFirstPull()
        let timedResult = await timedRun.value
        let coalescedResult = await coalescedRun.value
        await stream.waitForPullCount(2)

        #expect(timedResult.status == .timedOut)
        #expect(coalescedResult.status == .coalesced)
        #expect(await stream.events == [
            "relationship.pull.manual_refresh",
            "relationship.pull.local_change",
            "relationship.push.local_change",
        ])
    }

    @Test func pendingWritesStreamIsNotCutOffByTheRunTimeout() async {
        let slowDrain = SlowPendingWritesStream(duration: .milliseconds(300))
        let coordinator = PaeoniaSyncService(
            streams: [slowDrain],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            syncTimeoutNanoseconds: 50_000_000
        )
        await coordinator.configure(session: .test())

        let result = await coordinator.runOnce(reason: .localChange)

        #expect(result.status == .succeeded)
        #expect(await slowDrain.finished)
    }
}

private actor SlowPendingWritesStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .pendingOperations
    private let duration: Duration
    private(set) var finished = false

    init(duration: Duration) {
        self.duration = duration
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    func pull(context _: SyncContext) -> SyncCursor? {
        nil
    }

    func push(context _: SyncContext) async throws {
        try await Task.sleep(for: duration)
        finished = true
    }
}
