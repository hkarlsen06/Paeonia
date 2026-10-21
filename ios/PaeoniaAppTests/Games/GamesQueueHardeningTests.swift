import Foundation
import Testing
@testable import PaeoniaApp

/// Fails the upload of every reservation in `goneReservations`, the way the
/// server answers a reservation it already cleaned up.
private final class ExpiringUploadTransfer: GameDrawingTransferring, @unchecked Sendable {
    private let lock = NSLock()
    private var gone: Set<UUID> = []
    private var reserved: [UUID] = []
    private var bytes: [Data] = []

    var reserveOperationIDs: [UUID] { lock.withLock { reserved } }
    var uploadedBytes: [Data] { lock.withLock { bytes } }

    func expire(_ reserveOperationID: UUID) {
        lock.withLock { _ = gone.insert(reserveOperationID) }
    }

    func uploadDrawing(
        _ data: Data,
        parent _: GameUploadParent,
        coupleID _: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID { // swiftlint:disable:this async_without_await
        let isGone = lock.withLock {
            reserved.append(reserveOperation.id)
            return gone.contains(reserveOperation.id)
        }
        if isGone {
            throw PaeoniaConvexError.server(code: "42501", message: "media upload reservation is not available")
        }
        lock.withLock { bytes.append(data) }
        return GameFixture.assetID
    }

    func downloadDrawing(mediaAssetID _: UUID) async throws -> Data { // swiftlint:disable:this async_without_await
        throw ScriptedGamesGateway.Failure()
    }
}

/// The queued Games writes: how they wait, how often a refusal is tried, and how
/// the cache orders the answers they read.
@MainActor
struct GamesQueueHardeningTests {
    private let environment = GamesTestEnvironment(
        state: GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    )
    private let clientID = UUID()
    private let serverError = PaeoniaConvexError.server(code: nil, message: "Server Error")

    init() {
        // The server answers the read that follows each move it takes.
        environment.gateway.setStateToLoad(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .guessing, turn: GameFixture.me)
            )
        )
    }

    private func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: SyncClientOperation(
                    clientID: clientID,
                    clientSequence: sequence,
                    localCreatedAt: GameFixture.now
                ),
                operationKind: kind,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    private func drain(transfer: any GameDrawingTransferring) -> PendingSyncOperationDrainStream {
        let gateway = environment.gateway
        let cache = environment.cache
        return PendingSyncOperationDrainStream(handlers: [
            PickDrawWordPendingOperationHandler(gateway: gateway, cache: cache, drawingStore: environment.drawingStore),
            SubmitGameDrawingPendingOperationHandler(
                gateway: gateway,
                transfer: transfer,
                cache: cache,
                drawingStore: environment.drawingStore
            ),
            SubmitGameGuessPendingOperationHandler(gateway: gateway, cache: cache),
            GameResultSeenPendingOperationHandler(gateway: gateway, cache: cache),
        ], retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0))
    }

    private func runDrain(transfer: any GameDrawingTransferring? = nil) async {
        try? await drain(transfer: transfer ?? environment.transfer).push(context: syncContext(environment.pending))
    }

    private func drawingPayload(reserve: SyncClientOperation, renewedAt: Date? = nil) -> GameSubmitDrawingPayload {
        var payload = GameSubmitDrawingPayload(
            gameID: GameFixture.gameID,
            roundID: GameFixture.roundID,
            coupleID: DeveloperScenarioFixture.coupleID,
            drawingData: Data([7, 7, 7]),
            reserveOperation: reserve,
            finalizeOperation: SyncClientOperation(clientID: clientID, clientSequence: 11)
        )
        payload.renewedAt = renewedAt
        return payload
    }

    // MARK: An upload the server cleaned up

    @Test func aDrawingWhoseUploadWasCleanedUpUploadsTheKeptBytesAgain() async throws {
        let transfer = ExpiringUploadTransfer()
        let reserve = SyncClientOperation(clientID: clientID, clientSequence: 10)
        transfer.expire(reserve.id)
        try await enqueue(.submitGameDrawing, drawingPayload(reserve: reserve), sequence: 1)

        await runDrain(transfer: transfer)

        #expect(environment.gateway.submittedDrawings.map(\.roundID) == [GameFixture.roundID])
        #expect(transfer.uploadedBytes == [Data([7, 7, 7])])
        #expect(Set(transfer.reserveOperationIDs).count == 2)
        #expect(await environment.queued(.submitGameDrawing).isEmpty)
    }

    @Test func aDrawingRenewedMomentsAgoIsNotRenewedAgain() async throws {
        let transfer = ExpiringUploadTransfer()
        let reserve = SyncClientOperation(clientID: clientID, clientSequence: 10)
        transfer.expire(reserve.id)
        try await enqueue(.submitGameDrawing, drawingPayload(reserve: reserve, renewedAt: Date()), sequence: 1)

        await runDrain(transfer: transfer)

        #expect(transfer.reserveOperationIDs == [reserve.id])
        #expect(await environment.queued(.submitGameDrawing).count == 1)
    }

    // MARK: Result seen

    @Test func theSeenMarkGoesOutAfterTheGuessThatEndedTheRound() async throws {
        let guess = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now
        )
        try await enqueue(.submitGameGuess, guess, sequence: 1)
        try await enqueue(
            .markGameRoundResultSeen,
            GameResultSeenPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now),
            sequence: 2
        )

        await runDrain()

        #expect(environment.gateway.calls.filter { ["guess", "resultSeen"].contains($0) } == ["guess", "resultSeen"])
        #expect(environment.gateway.resultSeenRounds == [GameFixture.roundID])
        #expect(await environment.queued(.markGameRoundResultSeen).isEmpty)
    }

    // MARK: Refusals

    @Test func onlyRefusalsFromTheServerCountTowardDroppingAMove() async throws {
        let guess = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "cat",
            isCorrect: false,
            createdAt: GameFixture.now
        )
        try await enqueue(.submitGameGuess, guess, sequence: 1)
        let gateway = environment.gateway

        // Two tries without a connection, then one refusal the phone has no rule for.
        gateway.fail("guess")
        await runDrain()
        await runDrain()
        gateway.unfail("guess")
        gateway.setGuessError(serverError)
        await runDrain()
        #expect(await environment.queued(.submitGameGuess).count == 1)

        // The third refusal from the server drops it.
        await runDrain()
        await runDrain()
        #expect(await environment.queued(.submitGameGuess).isEmpty)
    }

    // MARK: Acknowledged moves

    @Test func anAcceptedPickReadsTheServersStateBeforeLeavingTheQueue() async throws {
        let picked = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me, roundID: GameFixture.nextRoundID),
            round: GameFixture.round(id: GameFixture.nextRoundID, state: .drawing, drawer: GameFixture.me)
        )
        environment.gateway.setStateToLoad(picked)
        let pick = GamePickWordPayload(
            gameID: GameFixture.gameID,
            roundID: GameFixture.nextRoundID,
            choice: .medium,
            word: "umbrella",
            wordID: "en-medium-umbrella",
            points: 2,
            createdAt: GameFixture.now
        )
        try await enqueue(.pickDrawWord, pick, sequence: 1)

        await runDrain()

        #expect(await environment.queued(.pickDrawWord).isEmpty)
        #expect(await environment.cache.document(ownerUserID: GameFixture.me).state == picked)
    }

    // MARK: Cache order

    @Test func aReadThatWasOnItsWayDuringAPurgeIsNotSaved() async {
        let cache = InMemoryGamesCache()
        let state = GameFixture.state(settings: GameFixture.settings(), game: nil)

        let ticket = await cache.beginFetch()
        await cache.clearAll()
        let saved = await cache.saveFetchedState(state, ownerUserID: GameFixture.me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == nil)
    }

    @Test func aFileCacheReadThatWasOnItsWayDuringAPurgeIsNotSaved() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileGamesCache(directoryURL: directory)

        let ticket = await cache.beginFetch()
        await cache.clearAll()
        let saved = await cache.saveFetchedState(
            GameFixture.state(settings: GameFixture.settings(), game: nil),
            ownerUserID: GameFixture.me,
            ticket: ticket
        )

        #expect(!saved)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == nil)
    }

    @Test func aLateStateWithoutTheSeenMarkNeverReplacesOneWithIt() async {
        let cache = InMemoryGamesCache()
        func solved(seen: Bool) -> RemoteDrawAndGuessState {
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
                round: GameFixture.round(
                    state: .solved,
                    drawer: GameFixture.partner,
                    hasDrawing: true,
                    resultSeenBy: seen ? [GameFixture.me] : []
                )
            )
        }
        await cache.saveState(solved(seen: true), ownerUserID: GameFixture.me)

        // A live update sent before the mark landed arrives late.
        await cache.saveState(solved(seen: false), ownerUserID: GameFixture.me)

        #expect(await cache.document(ownerUserID: GameFixture.me).state == solved(seen: true))
    }

    @Test func anOlderReadThatAnswersLastDoesNotReplaceANewerOne() async {
        let cache = InMemoryGamesCache()
        let older = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me)
        )
        let newer = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil)
        )

        let first = await cache.beginFetch()
        let second = await cache.beginFetch()
        _ = await cache.saveFetchedState(newer, ownerUserID: GameFixture.me, ticket: second)
        let savedOlder = await cache.saveFetchedState(older, ownerUserID: GameFixture.me, ticket: first)

        #expect(!savedOlder)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == newer)
    }
}
