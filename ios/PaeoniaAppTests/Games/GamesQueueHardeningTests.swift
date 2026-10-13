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

    func uploadDrawing( // swiftlint:disable:this function_parameter_count
        _ data: Data,
        gameID _: UUID,
        roundID _: UUID,
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

private actor AcceptingMemoryUploader: MemoryMediaUploading {
    func uploadMedia(
        _: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult { // swiftlint:disable:this async_without_await
        MemoryMediaUploadResult(memoryMediaID: memoryMediaID, mediaAssetID: UUID())
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
            GameFixture.state(settings: GameFixture.settings(), game: GameFixture.game(state: .guessing, turn: GameFixture.me))
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
            SaveGameRoundPendingOperationHandler(
                gateway: gateway,
                mediaUploader: AcceptingMemoryUploader(),
                cache: cache,
                transfer: transfer,
                drawingStore: environment.drawingStore
            ),
        ])
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

    // MARK: Save to Memories

    @Test func aSaveWaitsForTheGuessThatFinishesTheRound() async throws {
        let image = try #require(DrawAndGuessImageRenderer.render(GameFixture.umbrella()))
        let guess = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now
        )
        let save = GameSaveRoundPayload(
            roundID: GameFixture.roundID,
            coupleID: DeveloperScenarioFixture.coupleID,
            memoryID: UUID(),
            memoryMediaID: UUID(),
            imageData: image,
            memoryDate: "2026-01-01",
            reserveOperation: SyncClientOperation(clientID: clientID, clientSequence: 20),
            finalizeOperation: SyncClientOperation(clientID: clientID, clientSequence: 21)
        )
        try await enqueue(.submitGameGuess, guess, sequence: 1)
        try await enqueue(.saveGameRoundToMemories, save, sequence: 2)
        environment.gateway.fail("guess")

        await runDrain()

        #expect(!environment.gateway.calls.contains("saveRound"))
        #expect(await environment.queued(.saveGameRoundToMemories).count == 1)
    }

    private func saveWithoutImage() -> GameSaveRoundPayload {
        GameSaveRoundPayload(
            roundID: GameFixture.roundID,
            coupleID: DeveloperScenarioFixture.coupleID,
            memoryID: UUID(),
            memoryMediaID: UUID(),
            imageData: nil,
            memoryDate: "2026-01-01",
            reserveOperation: SyncClientOperation(clientID: clientID, clientSequence: 20),
            finalizeOperation: SyncClientOperation(clientID: clientID, clientSequence: 21)
        )
    }

    private func solved(hasDrawing: Bool) -> RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            round: GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: hasDrawing)
        )
    }

    @Test func aSaveWithoutAnImageWaitsForTheDrawersDrawingThenRendersIt() async throws {
        // The cache starts from this round. The environment's state already has its drawing,
        // and the cache never goes back to a state that lost it.
        await environment.cache.clearAll()
        await environment.cache.saveState(solved(hasDrawing: false), ownerUserID: GameFixture.me)
        environment.gateway.setRoundToLoad(GameFixture.round(state: .solved, drawer: GameFixture.partner))
        try await enqueue(.saveGameRoundToMemories, saveWithoutImage(), sequence: 1)

        await runDrain()
        #expect(!environment.gateway.calls.contains("saveRound"))
        #expect(await environment.queued(.saveGameRoundToMemories).count == 1)

        // The drawer's drawing reaches the server.
        await environment.cache.saveState(solved(hasDrawing: true), ownerUserID: GameFixture.me)
        await runDrain()

        #expect(environment.gateway.calls.contains("saveRound"))
        #expect(environment.transfer.downloads == [GameFixture.assetID])
        #expect(await environment.queued(.saveGameRoundToMemories).isEmpty)
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
        await cache.saveFetchedState(newer, ownerUserID: GameFixture.me, ticket: second)
        let savedOlder = await cache.saveFetchedState(older, ownerUserID: GameFixture.me, ticket: first)

        #expect(!savedOlder)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == newer)
    }
}

// MARK: Save to Memories after the round left the cache

extension GamesQueueHardeningTests {
    @Test func aSaveRetriesWhenTheRoundCannotBeReadAfterAPurge() async throws {
        // The privacy purge emptied the cache and kept the queued save.
        await environment.cache.clearAll()
        try await enqueue(.saveGameRoundToMemories, saveWithoutImage(), sequence: 1)
        environment.gateway.fail("loadRound")

        await runDrain()
        #expect(!environment.gateway.calls.contains("saveRound"))
        #expect(await environment.queued(.saveGameRoundToMemories).count == 1)
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me).isEmpty)

        // Access is back and the server has the round.
        environment.gateway.unfail("loadRound")
        environment.gateway.setRoundToLoad(
            GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)
        )
        await runDrain()

        #expect(environment.gateway.calls.contains("saveRound"))
        #expect(await environment.queued(.saveGameRoundToMemories).isEmpty)
    }

    @Test func aSaveFindsItsRoundByIDWhenItIsNoLongerAmongTheRecentRounds() async throws {
        let newer = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me, roundID: GameFixture.nextRoundID),
            round: GameFixture.round(id: GameFixture.nextRoundID, state: .drawing, drawer: GameFixture.me)
        )
        await environment.cache.saveState(newer, ownerUserID: GameFixture.me)
        environment.gateway.setStateToLoad(newer)
        environment.gateway.setRoundToLoad(
            GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)
        )
        try await enqueue(.saveGameRoundToMemories, saveWithoutImage(), sequence: 1)

        await runDrain()

        #expect(environment.gateway.calls.contains("saveRound"))
        #expect(environment.transfer.downloads == [GameFixture.assetID])
        #expect(await environment.queued(.saveGameRoundToMemories).isEmpty)
    }

    @Test func aSaveForARoundTheServerDoesNotHaveIsDropped() async throws {
        await environment.cache.clearAll()
        try await enqueue(.saveGameRoundToMemories, saveWithoutImage(), sequence: 1)

        await runDrain()

        #expect(!environment.gateway.calls.contains("saveRound"))
        #expect(await environment.queued(.saveGameRoundToMemories).isEmpty)
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me) == [.saveRejected])
    }
}
