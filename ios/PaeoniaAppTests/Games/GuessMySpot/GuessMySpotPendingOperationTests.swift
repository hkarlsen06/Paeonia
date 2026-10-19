import Foundation
import Testing
@testable import PaeoniaApp

// The protocol is async, and the stand-in answers at once.
// swiftlint:disable async_without_await

/// Records Guess my spot calls and answers with what a test sets.
final class ScriptedGuessMySpotGateway: GuessMySpotGateway, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var _calls: [String] = []
    private var _sentDetails: [GuessMySpotSendDetails] = []
    private var _state: RemoteGuessMySpotState?
    private var _sendError: PaeoniaConvexError?
    private var _guessError: PaeoniaConvexError?
    let assetID = UUID()

    var calls: [String] { lock.withLock { _calls } }
    var sentDetails: [GuessMySpotSendDetails] { lock.withLock { _sentDetails } }

    func setState(_ state: RemoteGuessMySpotState?) { lock.withLock { _state = state } }
    func setSendError(_ error: PaeoniaConvexError?) { lock.withLock { _sendError = error } }
    func setGuessError(_ error: PaeoniaConvexError?) { lock.withLock { _guessError = error } }

    private func note(_ call: String) { lock.withLock { _calls.append(call) } }

    func loadGuessMySpot() async throws -> RemoteGuessMySpotState {
        note("load")
        guard let state = lock.withLock({ _state }) else { throw Failure() }
        return state
    }

    func ensureGuessMySpotGame() async throws -> RemoteGuessMySpotEnsureResult {
        note("ensure")
        return RemoteGuessMySpotEnsureResult(gameID: UUID(), created: true)
    }

    func uploadGuessMySpotPhoto( // swiftlint:disable:this function_parameter_count
        _: Data,
        width _: Int,
        height _: Int,
        roundID _: UUID,
        coupleID _: UUID,
        reserve _: SyncClientOperation,
        finalize _: SyncClientOperation
    ) async throws -> UUID {
        note("upload")
        return assetID
    }

    func sendGuessMySpotPhoto(
        _ details: GuessMySpotSendDetails,
        mediaAssetID: UUID,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
        note("send")
        lock.withLock { _sentDetails.append(details) }
        if let error = lock.withLock({ _sendError }) { throw error }
        return RemoteGuessMySpotRound(
            id: details.roundID, roundNumber: details.roundNumber, senderUserID: GameFixture.me,
            guesserUserID: GameFixture.partner, photoMediaAssetID: mediaAssetID, photoWidth: 4, photoHeight: 3,
            spotLatitude: details.spot.latitude, spotLongitude: details.spot.longitude, sentAt: GameFixture.now
        )
    }

    func submitGuessMySpotGuess(
        roundID: UUID,
        guess: GuessMySpotCoordinate,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
        note("guess")
        if let error = lock.withLock({ _guessError }) { throw error }
        var round = RemoteGuessMySpotRound(
            id: roundID, roundNumber: 1, senderUserID: GameFixture.partner, guesserUserID: GameFixture.me,
            photoMediaAssetID: UUID(), photoWidth: nil, photoHeight: nil, spotLatitude: 60, spotLongitude: 5,
            sentAt: GameFixture.now
        )
        round.guess = guess
        return round
    }

    func markGuessMySpotRevealSeen(roundID: UUID) async throws -> RemoteGuessMySpotRevealSeenResult {
        note("seen")
        return RemoteGuessMySpotRevealSeenResult(roundID: roundID, revealSeenAt: GameFixture.now)
    }

    func loadGuessMySpotHistory() async throws -> RemoteGuessMySpotHistory {
        throw Failure()
    }

    func deleteGuessMySpotRound(roundID: UUID, operation _: SyncClientOperation) async throws
        -> RemoteGuessMySpotDeleteResult {
        note("delete")
        return RemoteGuessMySpotDeleteResult(roundID: roundID, deletedAt: GameFixture.now)
    }
}

/// Remembers what the send handler put in the shared media image cache.
actor RecordingImageCache: MemoryMediaImageCacheWriting {
    private(set) var cached: [UUID: Data] = [:]

    func cacheImageData(_ data: Data, for mediaAssetID: UUID) {
        cached[mediaAssetID] = data
    }
}

// swiftlint:enable async_without_await

/// How queued Guess my spot moves reach the server: their order, what a refusal
/// does, and that the photo is never lost before the server has it.
struct GuessMySpotPendingOperationTests {
    let gateway = ScriptedGuessMySpotGateway()
    let cache = InMemoryGuessMySpotCache()
    let pending = InMemoryPendingSyncOperationRepository()
    let photos = InMemoryGuessMySpotPhotoStore()
    let imageCache = RecordingImageCache()
    let roundID = UUID()
    let jpeg = Data("photo".utf8)
    let spot = GuessMySpotCoordinate(latitude: 60.39, longitude: 5.32)

    init() throws {
        gateway.setState(RemoteGuessMySpotState(
            userID: GameFixture.me, partnerUserID: GameFixture.partner, coupleID: UUID(), dataEpoch: "",
            game: nil, currentRound: nil, previousRound: nil
        ))
        try photos.save(jpeg, ownerUserID: GameFixture.me, roundID: roundID)
    }

    private func sendHandler(placeName: String? = "Bergen, Norway") -> GuessMySpotSendPendingOperationHandler {
        GuessMySpotSendPendingOperationHandler(
            gateway: gateway,
            cache: cache,
            photos: photos,
            namer: FixedGuessMySpotPlaceNamer(name: placeName),
            imageCache: imageCache
        )
    }

    private func sendPayload(placeName: String? = nil, renewedAt: Date? = nil) -> GuessMySpotSendPayload {
        var payload = GuessMySpotSendPayload(
            details: GuessMySpotSendDetails(
                roundID: roundID, roundNumber: 1, spot: spot, placeName: placeName, takenOn: "2024-06-12"
            ),
            coupleID: UUID(),
            width: 4,
            height: 3,
            reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
            finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2),
            createdAt: GameFixture.now
        )
        payload.renewedAt = renewedAt
        return payload
    }

    private func guess(_ round: UUID? = nil) -> GuessMySpotGuessPayload {
        GuessMySpotGuessPayload(roundID: round ?? roundID, guess: spot, createdAt: GameFixture.now)
    }

    private func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: GameFixture.me,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: GameFixture.now),
            operationKind: kind,
            idempotencyScope: "guess-my-spot",
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

    // MARK: Send

    @Test func aSendUploadsThePhotoSendsTheRoundAndForgetsTheLocalCopy() async throws {
        #expect(try await send(sendHandler(), .guessMySpotSend, sendPayload(placeName: "Bergen")) == .succeeded)
        #expect(gateway.calls == ["upload", "send", "load"])
        #expect(gateway.sentDetails.first?.placeName == "Bergen")
        #expect(photos.photo(ownerUserID: GameFixture.me, roundID: roundID) == nil)
        // This phone never downloads its own photo.
        #expect(await imageCache.cached[gateway.assetID] == jpeg)
    }

    @Test func anAcceptedSendKeepsThePhotoUntilTheStateIsRead() async throws {
        // The read after the send fails, so the whole send retries and needs the photo again.
        gateway.setState(nil)
        let result = try await send(sendHandler(), .guessMySpotSend, sendPayload(placeName: "Bergen"))
        guard case .retry = result else {
            Issue.record("Expected a retry while the state can't be read")
            return
        }
        #expect(photos.photo(ownerUserID: GameFixture.me, roundID: roundID) == jpeg)
        #expect(await cache.document(ownerUserID: GameFixture.me).refusedMoves.isEmpty)
    }

    @Test func aSendMadeOfflineNamesThePlaceBeforeItGoes() async throws {
        #expect(try await send(sendHandler(placeName: "Bergen, Norway"), .guessMySpotSend, sendPayload()) == .succeeded)
        #expect(gateway.sentDetails.first?.placeName == "Bergen, Norway")
    }

    @Test func aSendWaitsBehindAnEarlierGuess() async throws {
        try await enqueue(.guessMySpotGuess, guess(UUID()), sequence: 1)
        #expect(try await send(sendHandler(), .guessMySpotSend, sendPayload(), sequence: 2) == .retry(after: nil))
        #expect(gateway.calls.isEmpty)
    }

    @Test func aRefusedSendKeepsThePhotoForTheScreenToPutBack() async throws {
        gateway.setSendError(.server(code: "23514", message: "it isn't your turn"))
        let payload = sendPayload(placeName: "Bergen")
        let result = try await send(sendHandler(), .guessMySpotSend, payload)
        guard case .terminalFailure = result else {
            Issue.record("Expected the send to drop")
            return
        }
        let refused = await cache.document(ownerUserID: GameFixture.me).refusedMoves
        #expect(refused == [GuessMySpotRefusedMove(roundID: roundID, send: payload)])
        #expect(photos.photo(ownerUserID: GameFixture.me, roundID: roundID) == jpeg)
    }

    @Test func aSendWhoseUploadRanOutQueuesAgainWithANewUpload() async throws {
        gateway.setSendError(.server(code: "23514", message: "guess my spot photo is not usable"))
        let result = try await send(sendHandler(), .guessMySpotSend, sendPayload(placeName: "Bergen"))
        guard case .terminalFailure = result else {
            Issue.record("Expected the old write to retire")
            return
        }
        let queued = try await pending.inFlightOperations(ownerUserID: GameFixture.me, kind: .guessMySpotSend)
        let renewed = try #require(queued.first?.requestData.flatMap {
            try? JSONDecoder().decode(GuessMySpotSendPayload.self, from: $0)
        })
        #expect(renewed.renewedAt != nil)
        #expect(photos.photo(ownerUserID: GameFixture.me, roundID: roundID) == jpeg)
        #expect(await cache.document(ownerUserID: GameFixture.me).refusedMoves.isEmpty)
    }

    @Test func aSendWhosePhotoAssetIsMissingAlsoUploadsAgain() async throws {
        let message = "guess my spot photo is not available"
        gateway.setSendError(.server(code: PaeoniaConvexError.accessDeniedCode, message: message))
        let result = try await send(sendHandler(), .guessMySpotSend, sendPayload(placeName: "Bergen"))
        guard case .terminalFailure = result else {
            Issue.record("Expected the old write to retire")
            return
        }
        let queued = try await pending.inFlightOperations(ownerUserID: GameFixture.me, kind: .guessMySpotSend)
        #expect(queued.count == 1)
        #expect(photos.photo(ownerUserID: GameFixture.me, roundID: roundID) == jpeg)
    }

    @Test func aSendWhosePhotoIsGoneDropsWithANotice() async throws {
        photos.remove(ownerUserID: GameFixture.me, roundID: roundID)
        let result = try await send(sendHandler(), .guessMySpotSend, sendPayload())
        guard case .terminalFailure = result else {
            Issue.record("Expected the send to drop")
            return
        }
        #expect(gateway.calls.isEmpty)
        let refused = await cache.document(ownerUserID: GameFixture.me).refusedMoves
        #expect(refused == [GuessMySpotRefusedMove(roundID: roundID)])
    }

    // MARK: Guess and seen

    @Test func aGuessAnotherPhoneBeatLeavesOnlyOnceTheStateIsHere() async throws {
        gateway.setGuessError(.server(code: "23514", message: "this round already has a guess"))
        let handler = GuessMySpotGuessPendingOperationHandler(gateway: gateway, cache: cache)
        #expect(try await send(handler, .guessMySpotGuess, guess()) == .succeeded)
        #expect(await cache.document(ownerUserID: GameFixture.me).refusedMoves.isEmpty)

        gateway.setState(nil)
        let retried = try await send(handler, .guessMySpotGuess, guess())
        guard case .retry = retried else {
            Issue.record("Expected a retry while the state can't be read")
            return
        }
    }

    @Test func aGuessWaitsBehindAnEarlierSend() async throws {
        try await enqueue(.guessMySpotSend, sendPayload(), sequence: 1)
        let handler = GuessMySpotGuessPendingOperationHandler(gateway: gateway, cache: cache)
        #expect(try await send(handler, .guessMySpotGuess, guess(), sequence: 2) == .retry(after: nil))
        #expect(!gateway.calls.contains("guess"))
    }

    @Test func aSeenMarkWaitsForTheGuessOfItsRound() async throws {
        try await enqueue(.guessMySpotGuess, guess(), sequence: 1)
        let handler = GuessMySpotRevealSeenOperationHandler(gateway: gateway, cache: cache)
        let payload = GuessMySpotRevealSeenPayload(roundID: roundID, createdAt: GameFixture.now)
        #expect(try await send(handler, .guessMySpotRevealSeen, payload) == .retry(after: nil))
        let other = GuessMySpotRevealSeenPayload(roundID: UUID(), createdAt: GameFixture.now)
        #expect(try await send(handler, .guessMySpotRevealSeen, other) == .succeeded)
    }

    @Test func theQueueReadsBackAsPendingWork() async throws {
        try await enqueue(.guessMySpotSend, sendPayload(), sequence: 1)
        try await enqueue(.guessMySpotGuess, guess(), sequence: 2)
        let seen = GuessMySpotRevealSeenPayload(roundID: roundID, createdAt: GameFixture.now)
        try await enqueue(.guessMySpotRevealSeen, seen, sequence: 3)
        let work = try #require(await GuessMySpotPendingWork.load(from: pending, ownerUserID: GameFixture.me))
        #expect(work.sends.map(\.roundID) == [roundID])
        #expect(work.guesses[roundID] == spot)
        #expect(work.seenReveals == [roundID])
    }

    // MARK: Cache

    @Test func theCacheNeverTakesAnOlderStateAndClears() async {
        let gameID = UUID()
        let coupleID = UUID()
        func state(_ version: Int, epoch: String = "") -> RemoteGuessMySpotState {
            RemoteGuessMySpotState(
                userID: GameFixture.me, partnerUserID: nil, coupleID: coupleID, dataEpoch: epoch,
                game: RemoteGuessMySpotGame(
                    id: gameID, turnUserID: GameFixture.me, turnStartedAt: GameFixture.now,
                    sharedPoints: 0, myPoints: 0, partnerPoints: 0,
                    roundCount: 0, version: version, createdByUserID: GameFixture.me,
                    createdAt: GameFixture.now, updatedAt: GameFixture.now
                ),
                currentRound: nil, previousRound: nil
            )
        }
        await cache.saveState(state(3), ownerUserID: GameFixture.me)
        await cache.saveState(state(2), ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).state?.game?.version == 3)
        // After a restore the server's copy wins, whatever its version.
        await cache.saveState(state(1, epoch: "restored"), ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).state?.game?.version == 1)
        await cache.clearAll()
        #expect(await cache.document(ownerUserID: GameFixture.me).state == nil)
    }

    @Test func aFetchThatStartedBeforeALiveWriteIsNotSaved() async {
        let older = RemoteGuessMySpotState(
            userID: GameFixture.me, partnerUserID: nil, coupleID: UUID(), dataEpoch: "",
            game: nil, currentRound: nil, previousRound: nil
        )
        let ticket = await cache.beginFetch()
        await cache.saveState(older, ownerUserID: GameFixture.me)
        #expect(await cache.saveFetchedState(older, ownerUserID: GameFixture.me, ticket: ticket) == false)
    }

    @Test func aHistoryReadThatStartedBeforeAPurgeIsNotSaved() async {
        let history = RemoteGuessMySpotHistory(
            rounds: [],
            records: RemoteGuessMySpotRecords(
                sharedPoints: 5,
                myPoints: 5,
                partnerPoints: 0,
                mine: RemoteGuessMySpotGuesserRecord(guesses: 0, closestM: nil, averageM: nil),
                partner: RemoteGuessMySpotGuesserRecord(guesses: 0, closestM: nil, averageM: nil)
            )
        )
        let ticket = await cache.historyTicket()
        await cache.clearAll()
        await cache.saveHistory(history, ownerUserID: GameFixture.me, ticket: ticket)
        #expect(await cache.document(ownerUserID: GameFixture.me).history == nil)
        await cache.saveHistory(history, ownerUserID: GameFixture.me, ticket: await cache.historyTicket())
        #expect(await cache.document(ownerUserID: GameFixture.me).history == history)
    }

    @Test func aRefusedSendStaysUntilTheScreenForgetsIt() async {
        let refused = GuessMySpotRefusedMove(roundID: roundID, send: sendPayload())
        await cache.recordRefusedMove(refused, ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).refusedMoves == [refused])
        await cache.forgetRefusedMove(roundID: roundID, ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).refusedMoves.isEmpty)
    }

    @Test func theCacheIgnoresAnotherPersonsState() async {
        let other = RemoteGuessMySpotState(
            userID: UUID(), partnerUserID: nil, coupleID: UUID(), dataEpoch: "",
            game: nil, currentRound: nil, previousRound: nil
        )
        await cache.saveState(other, ownerUserID: GameFixture.me)
        #expect(await cache.document(ownerUserID: GameFixture.me).state == nil)
    }
}
