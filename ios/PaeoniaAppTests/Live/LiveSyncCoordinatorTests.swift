import Foundation
import Testing
@testable import PaeoniaApp

struct LiveSyncCoordinatorTests {
    /// Records each run and blocks until cancelled, then records the cancellation.
    private final class RecordingFeed: LiveFeed, @unchecked Sendable {
        let name: String
        let started = LockedBox<[SyncSession]>([])
        let finished = LockedBox<[SyncSession]>([])
        /// Counts runs that saw their cancellation, before the simulated write finishes.
        let cancelled = LockedBox<Int>(0)
        /// While true, a cancelled run keeps "writing" and does not finish.
        let holdsFinish = LockedBox<Bool>(false)
        /// Sessions that were still running when another session started.
        private let events = LockedBox<[String]>([])

        init(name: String) {
            self.name = name
        }

        var log: [String] {
            events.value
        }

        func run(session: SyncSession, live _: LiveQueryService) async {
            started.mutate { $0.append(session) }
            events.mutate { $0.append("start \(session.activeCoupleID?.uuidString.prefix(1) ?? "-")") }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            cancelled.mutate { $0 += 1 }
            while holdsFinish.value {
                try? await Task.sleep(for: .milliseconds(5))
            }
            // Simulates an in-flight repository write that finishes after cancellation.
            try? await Task.sleep(for: .milliseconds(20))
            finished.mutate { $0.append(session) }
            events.mutate { $0.append("end \(session.activeCoupleID?.uuidString.prefix(1) ?? "-")") }
        }
    }

    private struct NeverTransport: LiveQueryTransport {
        func updates(path _: String, args _: [String: String]) -> AsyncThrowingStream<Data, any Error> {
            AsyncThrowingStream { _ in }
        }
    }

    private static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    private static let coupleA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID()
    private static let coupleB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID()

    private static func session(couple: UUID?) -> SyncSession {
        SyncSession(userID: userID, activeCoupleID: couple)
    }

    private static func makeCoordinator(feeds: [any LiveFeed]) -> LiveSyncCoordinator {
        LiveSyncCoordinator(feeds: feeds, live: LiveQueryService(transport: NeverTransport()))
    }

    @Test func startRunsEveryFeedWithTheSession() async {
        let first = RecordingFeed(name: "first")
        let second = RecordingFeed(name: "second")
        let coordinator = Self.makeCoordinator(feeds: [first, second])
        let session = Self.session(couple: Self.coupleA)

        await coordinator.start(session: session)

        #expect(await waitUntil { first.started.value == [session] && second.started.value == [session] })
        #expect(await coordinator.isRunning)
        await coordinator.stop()
    }

    @Test func startingTheSameSessionAgainDoesNothing() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])
        let session = Self.session(couple: Self.coupleA)

        await coordinator.start(session: session)
        await coordinator.start(session: session)
        #expect(await waitUntil { feed.started.value.count == 1 })
        try? await Task.sleep(for: .milliseconds(30))

        #expect(feed.started.value == [session])
        await coordinator.stop()
    }

    @Test func aDifferentCoupleRestartsFeedsAfterTheOldRunFinished() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])

        await coordinator.start(session: Self.session(couple: Self.coupleA))
        #expect(await waitUntil { feed.started.value.count == 1 })
        await coordinator.start(session: Self.session(couple: Self.coupleB))

        // The old run must be completely finished before the new one begins.
        #expect(await waitUntil { feed.started.value.count == 2 })
        #expect(feed.log == ["start A", "end A", "start B"])
        await coordinator.stop()
    }

    @Test func aChangedUserRestartsFeeds() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])
        let other = SyncSession(userID: UUID(), activeCoupleID: Self.coupleA)

        await coordinator.start(session: Self.session(couple: Self.coupleA))
        #expect(await waitUntil { feed.started.value.count == 1 })
        await coordinator.start(session: other)

        #expect(await waitUntil { feed.started.value.count == 2 })
        #expect(feed.started.value.last == other)
        await coordinator.stop()
    }

    @Test func stopWaitsForFeedsToFinish() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])
        await coordinator.start(session: Self.session(couple: Self.coupleA))
        #expect(await waitUntil { feed.started.value.count == 1 })

        await coordinator.stop()

        #expect(feed.finished.value.count == 1)
        #expect(await !coordinator.isRunning)
    }

    @Test func stopDuringASessionChangeWaitsForOldFeedsAndBlocksTheStaleStart() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])
        let stale = Self.session(couple: Self.coupleA)
        await coordinator.start(session: stale)
        #expect(await waitUntil { feed.started.value.count == 1 })

        // The restart cancels the old feed and suspends while it finishes its last write.
        feed.holdsFinish.mutate { $0 = true }
        let restart = Task { await coordinator.start(session: Self.session(couple: Self.coupleB)) }
        #expect(await waitUntil { feed.cancelled.value == 1 })
        let stopReturned = LockedBox(false)
        let stopping = Task {
            await coordinator.stop()
            stopReturned.mutate { $0 = true }
        }
        try? await Task.sleep(for: .milliseconds(50))

        // Sign-out must not return while the old feed can still write.
        #expect(!stopReturned.value)
        feed.holdsFinish.mutate { $0 = false }
        await stopping.value
        #expect(feed.finished.value == [stale])
        await restart.value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(feed.started.value == [stale])
        #expect(await !coordinator.isRunning)
    }

    @Test func pauseStopsFeedsAndIgnoresStartsUntilResumed() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])
        let stale = Self.session(couple: Self.coupleA)
        let fresh = Self.session(couple: nil)
        await coordinator.start(session: stale)
        #expect(await waitUntil { feed.started.value.count == 1 })

        await coordinator.pause()
        // The purge can run now: the stale feed finished and cannot write again.
        #expect(feed.finished.value == [stale])
        await coordinator.start(session: stale)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(feed.started.value == [stale])

        await coordinator.resume()
        // Resume alone restarts nothing.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(feed.started.value == [stale])

        await coordinator.start(session: fresh)
        #expect(await waitUntil { feed.started.value == [stale, fresh] })
        await coordinator.stop()
    }

    @Test func nestedPausesNeedMatchingResumes() async {
        let feed = RecordingFeed(name: "feed")
        let coordinator = Self.makeCoordinator(feeds: [feed])
        await coordinator.pause()
        await coordinator.pause()
        await coordinator.resume()

        await coordinator.start(session: Self.session(couple: Self.coupleA))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(feed.started.value.isEmpty)

        await coordinator.resume()
        await coordinator.start(session: Self.session(couple: Self.coupleA))
        #expect(await waitUntil { feed.started.value.count == 1 })
        await coordinator.stop()
    }

    @Test func syncServicePausesLiveFeedsAroundAPrivacyPurge() async {
        let log = LockedBox<[String]>([])
        let live = LoggingLiveSync(log: log)
        let purger = LoggingPurger(log: log)
        let service = PaeoniaSyncService(
            streams: [],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            localPrivacyPurger: purger,
            liveSync: live
        )
        await service.configure(session: Self.session(couple: Self.coupleA))

        await service.purgeRelationshipAccess(ownerUserID: Self.userID, permanently: true)

        #expect(log.value == ["pause", "purge", "resume"])
    }
}

// swiftlint:disable async_without_await
private actor LoggingLiveSync: LiveSyncCoordinating {
    let log: LockedBox<[String]>

    init(log: LockedBox<[String]>) {
        self.log = log
    }

    func start(session _: SyncSession) async {
        log.mutate { $0.append("start") }
    }

    func stop() async {
        log.mutate { $0.append("stop") }
    }

    func pause() async {
        log.mutate { $0.append("pause") }
    }

    func resume() {
        log.mutate { $0.append("resume") }
    }
}

private struct LoggingPurger: LocalPrivacyPurging {
    let log: LockedBox<[String]>

    func purge(ownerUserID _: UUID, scope _: LocalPrivacyPurgeScope) async -> LocalPrivacyPurgeResult {
        log.mutate { $0.append("purge") }
        return .completed
    }

    func retryPendingPurges() async -> LocalPrivacyPurgeRetryResult {
        .completed
    }
}
// swiftlint:enable async_without_await
