import Foundation
import Testing
@testable import PaeoniaApp

/// Count and seen marks: what they wait for, and what a refusal does.
@MainActor
struct MindMeldMarkOperationTests {
    private let fixtures = MindMeldFixtures()
    private let env = MindMeldTestEnvironment(state: nil)
    private let roundID = UUID()
    private let gameID = UUID()

    init() {
        // The server answers the read that follows each write it takes.
        env.gateway.setStateToLoad(fixtures.state(current: fixtures.game(rounds: [fixtures.open(1)])))
    }

    private func lock(round: UUID? = nil, game: UUID? = nil) -> MindMeldLockPayload {
        MindMeldLockPayload(
            roundID: round ?? roundID,
            gameID: game ?? gameID,
            word: "ocean",
            createdAt: GameFixture.now
        )
    }

    private func count(_ round: UUID? = nil) -> MindMeldCountPayload {
        MindMeldCountPayload(roundID: round ?? roundID, createdAt: GameFixture.now)
    }

    private func revealSeen(_ round: UUID? = nil) -> MindMeldRevealSeenPayload {
        MindMeldRevealSeenPayload(roundID: round ?? roundID, createdAt: GameFixture.now)
    }

    private func endSeen(_ game: UUID? = nil) -> MindMeldEndSeenPayload {
        MindMeldEndSeenPayload(gameID: game ?? gameID, createdAt: GameFixture.now)
    }

    private var countHandler: CountMindMeldPendingOperationHandler {
        CountMindMeldPendingOperationHandler(gateway: env.gateway, cache: env.cache)
    }

    // MARK: Count it

    @Test func aCountGoesOutAndReadsTheStateBack() async throws {
        let result = try await env.send(countHandler, .countMindMeldRound, count())

        #expect(result == .succeeded)
        #expect(env.gateway.counts == [roundID])
        let state = await env.cache.document(ownerUserID: GameFixture.me).state
        #expect(state != nil)
    }

    @Test func aCountThatCannotBeDoneIsDroppedWithoutANotice() async throws {
        env.gateway.setMarkError(.server(code: "23514", message: "this round can't be counted"))

        let result = try await env.send(countHandler, .countMindMeldRound, count())

        guard case .terminalFailure = result else {
            Issue.record("The count should be dropped")
            return
        }
        #expect(await env.refusedWords().isEmpty)
    }

    @Test func aCountStaysQueuedWithoutAConnection() async throws {
        env.gateway.setMarkError(.http(status: 503, body: ""))

        await #expect(throws: PaeoniaConvexError.self) {
            try await env.send(countHandler, .countMindMeldRound, count())
        }
    }

    // MARK: Seen marks

    private var revealSeenHandler: MindMeldRevealSeenOperationHandler {
        MindMeldRevealSeenOperationHandler(gateway: env.gateway, cache: env.cache)
    }

    private var endSeenHandler: MindMeldEndSeenOperationHandler {
        MindMeldEndSeenOperationHandler(gateway: env.gateway, cache: env.cache)
    }

    @Test func aRevealSeenMarkWaitsForTheLockOfItsRound() async throws {
        try await env.enqueue(.lockMindMeldWord, lock(), sequence: 1)
        let payload = revealSeen()

        let waiting = try await env.send(revealSeenHandler, .markMindMeldRevealSeen, payload)
        #expect(waiting == .retry(after: nil))
        #expect(env.gateway.revealsSeen.isEmpty)

        // A lock-in of another round does not hold it back.
        let other = revealSeen(UUID())
        let sent = try await env.send(revealSeenHandler, .markMindMeldRevealSeen, other)
        #expect(sent == .succeeded)
        #expect(env.gateway.revealsSeen == [other.roundID])
    }

    @Test func aRevealSeenMarkReadsTheStateBack() async throws {
        let payload = revealSeen()

        let result = try await env.send(revealSeenHandler, .markMindMeldRevealSeen, payload)

        #expect(result == .succeeded)
        #expect(env.gateway.revealsSeen == [roundID])
        let state = await env.cache.document(ownerUserID: GameFixture.me).state
        #expect(state != nil)
    }

    @Test func aSeenMarkTheServerRefusesIsDroppedWithoutANotice() async throws {
        env.gateway.setMarkError(.server(code: "23514", message: "the round is not revealed yet"))

        let result = try await env.send(revealSeenHandler, .markMindMeldRevealSeen, revealSeen())

        guard case .terminalFailure = result else {
            Issue.record("The mark should be dropped")
            return
        }
        #expect(await env.refusedWords().isEmpty)
    }

    @Test func anEndSeenMarkWaitsForTheLocksOfItsGameAndForACount() async throws {
        let payload = endSeen()

        try await env.enqueue(.lockMindMeldWord, lock(), sequence: 1)
        let behindLock = try await env.send(endSeenHandler, .markMindMeldEndSeen, payload)
        #expect(behindLock == .retry(after: nil))

        let otherGame = endSeen(UUID())
        let free = try await env.send(endSeenHandler, .markMindMeldEndSeen, otherGame)
        #expect(free == .succeeded)

        // A count in flight can be what ends the game on the server.
        try await env.enqueue(.countMindMeldRound, count(), sequence: 2)
        let behindCount = try await env.send(endSeenHandler, .markMindMeldEndSeen, otherGame)
        #expect(behindCount == .retry(after: nil))
    }

    @Test func anEndSeenMarkGoesOutWhenNothingHoldsItBack() async throws {
        let payload = endSeen()

        let result = try await env.send(endSeenHandler, .markMindMeldEndSeen, payload)

        #expect(result == .succeeded)
        #expect(env.gateway.endsSeen == [gameID])
    }
}
