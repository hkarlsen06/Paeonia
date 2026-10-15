import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

// MARK: - Live feed

/// Opens one stream per subscription and lets a test push a result into the latest
/// stream for a path, like the server pushing a query update.
final class DailyPushTransport: LiveQueryTransport, @unchecked Sendable {
    private typealias Stream = (path: String, continuation: AsyncThrowingStream<Data, any Error>.Continuation)
    private let streams = LockedBox<[Stream]>([])
    let openedPaths = LockedBox<[String]>([])
    let openedArgs = LockedBox<[[String: String]]>([])

    func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        openedPaths.mutate { $0.append(path) }
        openedArgs.mutate { $0.append(args) }
        return AsyncThrowingStream { continuation in
            streams.mutate { $0.append((path, continuation)) }
        }
    }

    func push(_ rows: [DailyChallengeRemoteSnapshotRow], to path: String) async throws {
        let data = try PaeoniaConvexClient.encoder.encode(rows)
        _ = await waitUntil { streams.value.contains { $0.path == path } }
        streams.value.last { $0.path == path }?.continuation.yield(data)
    }
}

final class LockedSnapshotCache: DailyChallengeSnapshotCaching, @unchecked Sendable {
    private let rows = LockedBox<[UUID: DailyChallengeRemoteSnapshotRow]>([:])

    func load(ownerUserID: UUID) -> DailyChallengeRemoteSnapshotRow? {
        rows.value[ownerUserID]
    }

    func save(_ row: DailyChallengeRemoteSnapshotRow, ownerUserID: UUID) {
        rows.mutate { $0[ownerUserID] = row }
    }

    func clearAll() {
        rows.mutate { $0.removeAll() }
    }
}

/// Holds the shuffle request until a test opens it, like a slow network response.
actor GatedShuffleGateway: DailyChallengeGateway {
    private let response: DailyChallengeRemoteSnapshotRow
    private var started = false
    private var isOpen: Bool
    private var waiter: CheckedContinuation<Void, Never>?

    init(response: DailyChallengeRemoteSnapshotRow, isOpen: Bool = false) {
        self.response = response
        self.isOpen = isOpen
    }

    func hasStarted() -> Bool { started }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func shuffleQuestion(
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeRemoteSnapshotRow {
        started = true
        if !isOpen {
            await withCheckedContinuation { waiter = $0 }
        }
        return response
    }

    func loadTodaySnapshot() throws -> DailyChallengeRemoteSnapshotRow { response }
    func startDailyChallenge(operation _: SyncClientOperation) throws -> DailyChallengeRemoteSnapshotRow { response }
    func loadHistoryQuestions() throws -> [DailyQuestionRow] { [] }
    func loadHistoryAnswerDetails() throws -> [DailyAnswerDetailRow] { [] }
    func loadCoupleStreak() throws -> CoupleStreak { .none }
    func loadAnswerDetails(coupleDayID _: UUID) throws -> [DailyAnswerDetailRow] { [] }
    func submitAnswer(
        instanceID _: UUID,
        answerID _: UUID,
        payload _: DailyAnswerPayload,
        operation _: SyncClientOperation
    ) throws -> UUID { UUID() }
    func editTextAnswer(instanceID _: UUID, text _: String, operation _: SyncClientOperation) throws -> UUID { UUID() }
    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) throws -> UUID { UUID() }
}

@MainActor
func waitForDaily(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
