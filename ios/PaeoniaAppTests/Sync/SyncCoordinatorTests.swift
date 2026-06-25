import Foundation
import Testing
@testable import PaeoniaApp

struct SyncCoordinatorTests {
    @Test func runOncePullsBeforePushingEachStream() async {
        let relationshipStream = RecordingSyncStream(streamKey: .relationship)
        let profileStream = RecordingSyncStream(streamKey: .profile)
        let stateStore = InMemorySyncStateRepository()
        let coordinator = SyncCoordinator(
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

    @Test func failedStreamStopsRunBeforeLaterStreams() async {
        let relationshipStream = RecordingSyncStream(
            streamKey: .relationship,
            failure: .pull
        )
        let profileStream = RecordingSyncStream(streamKey: .profile)
        let stateStore = InMemorySyncStateRepository()
        let coordinator = SyncCoordinator(
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
        let coordinator = SyncCoordinator(
            streams: [RecordingSyncStream(streamKey: .relationship)],
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let result = await coordinator.runOnce(reason: .manualRefresh)

        #expect(result.status == .skippedNoSession)
        #expect(result.attemptedStreamCount == 0)
    }
}

private enum RecordingSyncStreamFailure: Sendable {
    case pull
    case push
}

private enum RecordingSyncStreamError: Error {
    case requestedFailure
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
