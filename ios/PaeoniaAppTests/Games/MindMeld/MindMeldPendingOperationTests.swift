import Foundation
import Testing
@testable import PaeoniaApp

/// How queued Mind Meld writes reach the server: the order they go in, what a
/// refusal does, and that no word is lost.
@MainActor
struct MindMeldPendingOperationTests {
    private let fixtures = MindMeldFixtures()
    private let env = MindMeldTestEnvironment(state: nil)
    private let roundID = UUID()
    private let gameID = UUID()

    init() {
        // The server answers the read that follows each write it takes.
        env.gateway.setStateToLoad(fixtures.state(current: fixtures.game(rounds: [fixtures.open(1)])))
    }

    private func operation(_ sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: GameFixture.now)
    }

    private func lock(round: UUID? = nil, game: UUID? = nil, word: String = "ocean") -> MindMeldLockPayload {
        MindMeldLockPayload(roundID: round ?? roundID, gameID: game ?? gameID, word: word, createdAt: GameFixture.now)
    }

    private var lockHandler: LockMindMeldWordPendingOperationHandler {
        LockMindMeldWordPendingOperationHandler(gateway: env.gateway, cache: env.cache)
    }

    private func sendLock(
        _ payload: MindMeldLockPayload,
        sequence: Int64 = 5
    ) async throws -> PendingSyncOperationSendResult {
        try await env.send(lockHandler, .lockMindMeldWord, payload, sequence: sequence)
    }

    private func refusedWords() async -> [MindMeldRefusedWord] {
        await env.refusedWords()
    }

    // MARK: Lock in

    @Test func aLockWaitsBehindAnEarlierLockOfThePerson() async throws {
        try await env.enqueue(.lockMindMeldWord, lock(round: UUID(), word: "first"), sequence: 1)

        let result = try await sendLock(lock(), sequence: 2)

        #expect(result == .retry(after: nil))
        #expect(env.gateway.locks.isEmpty)
    }

    @Test func aTakenLockReadsTheStateBackBeforeLeavingTheQueue() async throws {
        let before = await env.cache.document(ownerUserID: GameFixture.me).state
        #expect(before == nil)

        let result = try await sendLock(lock())

        #expect(result == .succeeded)
        let after = await env.cache.document(ownerUserID: GameFixture.me).state
        #expect(after != nil)
        #expect(env.gateway.calls == ["lock", "load"])
    }

    @Test func aLockStaysQueuedWhenTheReadBackFails() async throws {
        env.gateway.fail("load")

        let result = try await sendLock(lock())

        guard case let .retry(after) = result else {
            Issue.record("The lock should wait for a new try")
            return
        }
        // Soon, not after the usual minute.
        let wait = try #require(after).timeIntervalSinceNow
        #expect(wait > 0 && wait <= 15)
        #expect(await refusedWords().isEmpty)
    }

    @Test func aLockTheServerAlreadyHasReadsTheStateBack() async throws {
        env.gateway.setLockError(.server(code: "23505", message: "you already locked in a word this round"))

        let result = try await sendLock(lock())

        #expect(result == .succeeded)
        #expect(await refusedWords().isEmpty)
        let state = await env.cache.document(ownerUserID: GameFixture.me).state
        #expect(state != nil)
    }

    @Test func aRefusedLockIsDroppedAndTheWordIsKept() async throws {
        let payload = lock(word: "ocean")
        env.gateway.setLockError(.server(code: "23514", message: "that word was already used in this game"))

        let result = try await sendLock(payload)

        guard case .terminalFailure = result else {
            Issue.record("A refusal that a retry cannot fix drops the write")
            return
        }
        #expect(await refusedWords() == [MindMeldRefusedWord(roundID: roundID, word: "ocean")])
        // Taken once.
        #expect(await refusedWords().isEmpty)
    }

    @Test func aRefusalForAnUnknownReasonIsTriedThreeTimes() async throws {
        env.gateway.setLockError(.server(code: "XX000", message: "something broke"))
        let payload = lock()
        let queued = try snapshot(.lockMindMeldWord, payload, operation: operation(5))
        let context = syncContext(env.pending)

        await #expect(throws: PaeoniaConvexError.self) { try await lockHandler.send(queued, context: context) }
        await #expect(throws: PaeoniaConvexError.self) { try await lockHandler.send(queued, context: context) }
        let third = try await lockHandler.send(queued, context: context)

        guard case .terminalFailure = third else {
            Issue.record("The third unexplained refusal drops the lock")
            return
        }
        #expect(await refusedWords() == [MindMeldRefusedWord(roundID: roundID, word: "ocean")])
    }

    @Test func noConnectionKeepsTheLockQueuedForever() async throws {
        env.gateway.setLockError(.http(status: 503, body: ""))
        let queued = try snapshot(.lockMindMeldWord, lock(), operation: operation(5))
        let context = syncContext(env.pending)

        for _ in 0..<5 {
            await #expect(throws: PaeoniaConvexError.self) { try await lockHandler.send(queued, context: context) }
        }

        #expect(await refusedWords().isEmpty)
    }

    @Test func aRoundTheServerNoLongerHasDropsTheLockWithoutANotice() async throws {
        // A counted near miss removes the open round after it. The server answers 42501.
        env.gateway.setLockError(.server(code: "42501", message: "active entitled game access is required"))

        let result = try await sendLock(lock(round: UUID()))

        guard case .terminalFailure = result else {
            Issue.record("A word for a round that is gone can never land")
            return
        }
        #expect(await refusedWords().isEmpty)
    }

    @Test func aLostAccessKeepsTheLockQueued() async throws {
        let open = fixtures.open(1)
        env.gateway.setStateToLoad(fixtures.state(current: fixtures.game(rounds: [open])))
        env.gateway.setLockError(.server(code: "42501", message: "active entitled game access is required"))

        // The round is there, so the refusal is about access, which can come back.
        await #expect(throws: PaeoniaConvexError.self) { try await sendLock(lock(round: open.id)) }

        env.gateway.fail("load")
        await #expect(throws: PaeoniaConvexError.self) { try await sendLock(lock(round: UUID())) }
        #expect(await refusedWords().isEmpty)
    }

    // MARK: Reading the queue

    @Test func theQueueTurnsIntoPendingWork() async throws {
        let counted = UUID()
        let revealed = UUID()
        let ended = UUID()
        try await env.enqueue(.lockMindMeldWord, lock(word: "ocean"), sequence: 1)
        let count = MindMeldCountPayload(roundID: counted, createdAt: GameFixture.now)
        try await env.enqueue(.countMindMeldRound, count, sequence: 2)
        try await env.enqueue(
            .markMindMeldRevealSeen,
            MindMeldRevealSeenPayload(roundID: revealed, createdAt: GameFixture.now),
            sequence: 3
        )
        let endSeen = MindMeldEndSeenPayload(gameID: ended, createdAt: GameFixture.now)
        try await env.enqueue(.markMindMeldEndSeen, endSeen, sequence: 4)

        let work = await MindMeldPendingWork.load(from: env.pending, ownerUserID: GameFixture.me)

        #expect(work?.lockedWords == [roundID: "ocean"])
        #expect(work?.countedRounds == [counted])
        #expect(work?.seenReveals == [revealed])
        #expect(work?.seenEnds == [ended])
        #expect(work?.hasFailedMoveAttempt == false)
        #expect(work?.isStarting == false)
    }

    @Test func anotherPersonsQueueIsNotRead() async throws {
        try await env.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.partner,
                operation: operation(1),
                operationKind: .lockMindMeldWord,
                idempotencyScope: "mind-meld",
                requestData: try JSONEncoder().encode(lock())
            )
        )

        let work = await MindMeldPendingWork.load(from: env.pending, ownerUserID: GameFixture.me)

        #expect(work?.lockedWords.isEmpty == true)
    }
}
