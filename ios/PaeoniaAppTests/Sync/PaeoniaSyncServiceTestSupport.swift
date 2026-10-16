import Foundation
@testable import PaeoniaApp

struct SyncPrivacyPurgeCall: Equatable, Sendable {
    let ownerUserID: UUID
    let scope: LocalPrivacyPurgeScope
}

actor RecordingSyncPrivacyPurger {
    private(set) var calls: [SyncPrivacyPurgeCall] = []

    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) -> LocalPrivacyPurgeResult {
        calls.append(SyncPrivacyPurgeCall(ownerUserID: ownerUserID, scope: scope))
        return .completed
    }
}

extension RecordingSyncPrivacyPurger: LocalPrivacyPurging {}

actor AsyncCompletionProbe {
    private var completed = false

    var isCompleted: Bool {
        completed
    }

    func markCompleted() {
        completed = true
    }
}

enum RecordingSyncStreamFailure: Sendable {
    case pull
    case push
}

enum RecordingSyncStreamError: Error {
    case requestedFailure
}

actor BlockingFirstPullSyncStream {
    nonisolated let streamKey: SyncStreamKey
    private var recordedEvents: [String] = []
    private var firstPullStarted = false
    private var firstPullStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstPullReleaseContinuation: CheckedContinuation<Void, Never>?
    private var recordedCoupleIDs: [UUID?] = []
    private var cancellationCount = 0
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var pullCountWaiters: [CheckedContinuation<Void, Never>] = []

    init(streamKey: SyncStreamKey) {
        self.streamKey = streamKey
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    var events: [String] {
        recordedEvents
    }

    var pulledCoupleIDs: [UUID?] {
        recordedCoupleIDs
    }

    var pullCount: Int {
        recordedCoupleIDs.count
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

    func waitForCancellationCount(_ expectedCount: Int) async {
        if cancellationCount >= expectedCount {
            return
        }

        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    func waitForPullCount(_ expectedCount: Int) async {
        if recordedCoupleIDs.count >= expectedCount {
            return
        }

        await withCheckedContinuation { continuation in
            pullCountWaiters.append(continuation)
        }
    }

    private func recordCancellation() {
        cancellationCount += 1
        cancellationWaiters.forEach { $0.resume() }
        cancellationWaiters.removeAll()
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        recordedEvents.append("\(streamKey.rawValue).pull.\(context.reason.rawValue)")
        recordedCoupleIDs.append(context.session.activeCoupleID)
        pullCountWaiters.forEach { $0.resume() }
        pullCountWaiters.removeAll()

        if !firstPullStarted {
            firstPullStarted = true
            firstPullStartedContinuation?.resume()
            firstPullStartedContinuation = nil

            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    firstPullReleaseContinuation = continuation
                }
            } onCancel: {
                Task { await self.recordCancellation() }
            }
        }

        return SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 100),
            tieID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
    }

    func push(context: SyncContext) throws {
        recordedEvents.append("\(streamKey.rawValue).push.\(context.reason.rawValue)")
    }
}

extension BlockingFirstPullSyncStream: SyncStream {}

actor FailOnceSyncStream {
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

    func pull(context: SyncContext) throws -> SyncCursor? {
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

    func push(context: SyncContext) throws {
        recordedEvents.append("\(streamKey.rawValue).push.\(context.reason.rawValue)")
    }
}

extension FailOnceSyncStream: SyncStream {}

actor RecordingSyncStream {
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

    func pull(context: SyncContext) throws -> SyncCursor? {
        recordedEvents.append("\(streamKey.rawValue).pull.\(context.reason.rawValue)")

        if failure == .pull {
            throw RecordingSyncStreamError.requestedFailure
        }

        return SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 100),
            tieID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
    }

    func push(context: SyncContext) throws {
        recordedEvents.append("\(streamKey.rawValue).push.\(context.reason.rawValue)")

        if failure == .push {
            throw RecordingSyncStreamError.requestedFailure
        }
    }
}

extension RecordingSyncStream: SyncStream {}

actor RetryThenSucceedPendingOperationHandler {
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
    ) throws -> PendingSyncOperationSendResult {
        sendCount += 1
        waiters.forEach { $0.resume() }
        waiters.removeAll()

        if sendCount == 1 {
            throw RecordingSyncStreamError.requestedFailure
        }

        return .succeeded
    }
}

extension RetryThenSucceedPendingOperationHandler: PendingSyncOperationHandling {}

extension SyncSession {
    static func test() -> SyncSession {
        SyncSession(userID: .testUserID)
    }
}

extension UUID {
    static let testUserID: UUID = {
        guard let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111") else {
            preconditionFailure("Invalid test UUID")
        }

        return id
    }()
}
