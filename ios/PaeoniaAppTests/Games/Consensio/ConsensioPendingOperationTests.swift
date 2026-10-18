import Foundation
import Testing
@testable import PaeoniaApp

// The protocol is async, and the stand-in answers at once.
// swiftlint:disable async_without_await

/// Records Consensio calls and answers with what a test sets.
final class ScriptedConsensioGateway: ConsensioGateway, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var _calls: [String] = []
    private var _state: RemoteConsensioState?
    private var _placeError: PaeoniaConvexError?
    private var _guessError: PaeoniaConvexError?

    var calls: [String] { lock.withLock { _calls } }

    func setState(_ state: RemoteConsensioState?) { lock.withLock { _state = state } }
    func setPlaceError(_ error: PaeoniaConvexError?) { lock.withLock { _placeError = error } }
    func setGuessError(_ error: PaeoniaConvexError?) { lock.withLock { _guessError = error } }

    private func note(_ call: String) { lock.withLock { _calls.append(call) } }

    func loadConsensio() async throws -> RemoteConsensioState {
        note("load")
        guard let state = lock.withLock({ _state }) else { throw Failure() }
        return state
    }

    func ensureConsensioGame() async throws -> RemoteConsensioEnsureResult {
        note("ensure")
        return RemoteConsensioEnsureResult(gameID: UUID(), created: true)
    }

    func placeConsensioSpot(
        roundID: UUID,
        roundNumber _: Int,
        topic: ConsensioTopicChoice,
        spot: Int,
        operation _: SyncClientOperation
    ) async throws -> RemoteConsensioRound {
        note("place")
        if let error = lock.withLock({ _placeError }) { throw error }
        return RemoteConsensioRound(
            id: roundID, roundNumber: 1, placerUserID: GameFixture.me, guesserUserID: GameFixture.partner,
            topicID: nil, language: nil, subject: topic.subject, leftEnd: topic.leftEnd, rightEnd: topic.rightEnd,
            spot: spot, placedAt: GameFixture.now
        )
    }

    func guessConsensioSpot(roundID: UUID, guess: Int, operation _: SyncClientOperation) async throws
        -> RemoteConsensioRound {
        note("guess")
        if let error = lock.withLock({ _guessError }) { throw error }
        return RemoteConsensioRound(
            id: roundID, roundNumber: 1, placerUserID: GameFixture.partner, guesserUserID: GameFixture.me,
            topicID: nil, language: nil, subject: "Camping", leftEnd: "No", rightEnd: "Yes",
            spot: 50, placedAt: GameFixture.now, guess: guess
        )
    }

    func markConsensioRevealSeen(roundID: UUID) async throws -> RemoteConsensioRevealSeenResult {
        note("seen")
        return RemoteConsensioRevealSeenResult(roundID: roundID, revealSeenAt: GameFixture.now)
    }

    func loadConsensioHistory(beforeRoundNumber _: Int?, limit _: Int) async throws -> RemoteConsensioHistoryPage {
        throw Failure()
    }
}

// swiftlint:enable async_without_await

/// How queued Consensio moves reach the server: their order, what a refusal does,
/// and that nothing the person did is lost.
struct ConsensioPendingOperationTests {
    let gateway = ScriptedConsensioGateway()
    let cache = InMemoryConsensioCache()
    let pending = InMemoryPendingSyncOperationRepository()
    let roundID = UUID()

    init() {
        gateway.setState(RemoteConsensioState(
            userID: GameFixture.me, partnerUserID: GameFixture.partner, coupleID: UUID(), dataEpoch: "",
            game: nil, currentRound: nil, previousRound: nil
        ))
    }

    private func place(_ round: UUID? = nil) -> ConsensioPlacePayload {
        ConsensioPlacePayload(
            roundID: round ?? roundID, roundNumber: 1,
            topic: .own(subject: "Waffles", leftEnd: "No", rightEnd: "Yes"),
            spot: 40, createdAt: GameFixture.now
        )
    }

    private func guess(_ round: UUID? = nil) -> ConsensioGuessPayload {
        ConsensioGuessPayload(roundID: round ?? roundID, guess: 55, createdAt: GameFixture.now)
    }

    private func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: GameFixture.me,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: GameFixture.now),
            operationKind: kind,
            idempotencyScope: "consensio",
            requestData: try JSONEncoder().encode(payload)
        ))
    }

    private func send(
        _ handler: some PendingSyncOperationHandling,
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        sequence: Int64 = 5
    ) async throws -> PendingSyncOperationSendResult {
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: GameFixture.now)
        return try await handler.send(try snapshot(kind, payload, operation: operation), context: syncContext(pending))
    }

    @Test func aGuessWaitsBehindAnEarlierPlacement() async throws {
        try await enqueue(.placeConsensioSpot, place(UUID()), sequence: 1)
        let handler = ConsensioGuessPendingOperationHandler(gateway: gateway, cache: cache)
        #expect(try await send(handler, .guessConsensioSpot, guess(), sequence: 2) == .retry(after: nil))
        #expect(!gateway.calls.contains("guess"))
    }

    @Test func aPlacementSendsThenReadsTheState() async throws {
        let handler = ConsensioPlacePendingOperationHandler(gateway: gateway, cache: cache)
        #expect(try await send(handler, .placeConsensioSpot, place()) == .succeeded)
        #expect(gateway.calls == ["place", "load"])
    }

    @Test func aRefusedPlacementIsKeptForTheScreenToPutBack() async throws {
        gateway.setPlaceError(.server(code: "23514", message: "it isn't your turn"))
        let handler = ConsensioPlacePendingOperationHandler(gateway: gateway, cache: cache)
        let result = try await send(handler, .placeConsensioSpot, place())
        guard case .terminalFailure = result else {
            Issue.record("Expected the placement to drop")
            return
        }
        let refused = await cache.takeRefusedMoves(ownerUserID: GameFixture.me)
        #expect(refused == [ConsensioRefusedMove(roundID: roundID, topic: place().topic, spot: 40)])
    }

    @Test func aGuessAnotherPhoneBeatLeavesOnlyOnceTheStateIsHere() async throws {
        gateway.setGuessError(.server(code: "23514", message: "this round already has a guess"))
        let handler = ConsensioGuessPendingOperationHandler(gateway: gateway, cache: cache)
        #expect(try await send(handler, .guessConsensioSpot, guess()) == .succeeded)
        #expect(await cache.takeRefusedMoves(ownerUserID: GameFixture.me).isEmpty)

        gateway.setState(nil)
        let retried = try await send(handler, .guessConsensioSpot, guess())
        guard case .retry = retried else {
            Issue.record("Expected a retry while the state can't be read")
            return
        }
    }

    @Test func aSeenMarkWaitsForTheGuessOfItsRound() async throws {
        try await enqueue(.guessConsensioSpot, guess(), sequence: 1)
        let handler = ConsensioRevealSeenOperationHandler(gateway: gateway, cache: cache)
        let payload = ConsensioRevealSeenPayload(roundID: roundID, createdAt: GameFixture.now)
        #expect(try await send(handler, .markConsensioRevealSeen, payload) == .retry(after: nil))
        let other = ConsensioRevealSeenPayload(roundID: UUID(), createdAt: GameFixture.now)
        #expect(try await send(handler, .markConsensioRevealSeen, other) == .succeeded)
    }

    @Test func theCacheNeverTakesAnOlderStateAndClears() async {
        func state(_ version: Int) -> RemoteConsensioState {
            RemoteConsensioState(
                userID: GameFixture.me, partnerUserID: nil, coupleID: DeveloperScenarioFixture.coupleID, dataEpoch: "",
                game: RemoteConsensioGame(
                    id: DeveloperConsensioScenarioFactory.gameID, turnUserID: GameFixture.me,
                    turnStartedAt: GameFixture.now,
                    choices: [], sharedPoints: 0, roundCount: 0, version: version, createdByUserID: GameFixture.me,
                    createdAt: GameFixture.now, updatedAt: GameFixture.now
                ),
                currentRound: nil, previousRound: nil
            )
        }
        await cache.saveState(state(3), ownerUserID: GameFixture.me)
        await cache.saveState(state(2), ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).state?.game?.version == 3)
        await cache.clearAll()
        #expect(await cache.document(ownerUserID: GameFixture.me).state == nil)
    }
}
