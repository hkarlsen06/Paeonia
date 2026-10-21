import Foundation
import Testing
@testable import PaeoniaApp

/// Fixes for the queued Games moves and the files and cache they touch.
@MainActor
struct GamesHandlerFixTests {
    private let environment = GamesTestEnvironment(state: nil)
    private let clientID = UUID()

    init() {
        // The server answers the read that follows each move it takes.
        environment.gateway.setStateToLoad(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .guessing, turn: GameFixture.me)
            )
        )
    }

    private func operation(_ sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(clientID: clientID, clientSequence: sequence, localCreatedAt: GameFixture.now)
    }

    private func enqueue(
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        _ operation: SyncClientOperation
    ) async throws {
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: operation,
                operationKind: kind,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    private func pick(roundID: UUID = GameFixture.roundID) -> GamePickWordPayload {
        GamePickWordPayload(
            gameID: GameFixture.gameID,
            roundID: roundID,
            choice: .medium,
            word: "umbrella",
            wordID: "en-medium-umbrella",
            points: 2,
            createdAt: GameFixture.now
        )
    }

    private func drawing(roundID: UUID = GameFixture.roundID) -> GameSubmitDrawingPayload {
        GameSubmitDrawingPayload(
            gameID: GameFixture.gameID,
            roundID: roundID,
            coupleID: DeveloperScenarioFixture.coupleID,
            drawingData: Data([1, 2, 3]),
            reserveOperation: SyncClientOperation(clientID: clientID, clientSequence: 10),
            finalizeOperation: SyncClientOperation(clientID: clientID, clientSequence: 11)
        )
    }

    private func guess(_ text: String, correct: Bool = false, roundID: UUID = GameFixture.roundID) -> GameGuessPayload {
        GameGuessPayload(id: UUID(), roundID: roundID, guess: text, isCorrect: correct, createdAt: GameFixture.now)
    }

    // MARK: Result seen

    @Test func theResultSeenMarkWaitsForTheGiveUpAndThenGoesToTheServer() async throws {
        let giveUpOperation = operation(1)
        try await enqueue(
            .giveUpGameRound,
            GameGiveUpPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now),
            giveUpOperation
        )
        let mark = GameResultSeenPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now)
        let handler = GameResultSeenPendingOperationHandler(gateway: environment.gateway, cache: environment.cache)

        let waiting = try await handler.send(
            try snapshot(.markGameRoundResultSeen, mark, operation: operation(2)),
            context: syncContext(environment.pending)
        )
        #expect(waiting == .retry(after: nil))

        try await environment.pending.markSucceeded(clientOperationID: giveUpOperation.id, at: GameFixture.now)
        let sent = try await handler.send(
            try snapshot(.markGameRoundResultSeen, mark, operation: operation(2)),
            context: syncContext(environment.pending)
        )
        #expect(sent == .succeeded)
        #expect(environment.gateway.resultSeenRounds == [GameFixture.roundID])
    }

    // MARK: Privacy purge

    @Test func hidingAccessKeepsTheOwnUnsentDrawingsAndDropsThePartnersFiles() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileGameDrawingStore(directoryURL: directory)
        let asset = UUID()
        func fill() {
            store.saveDraft(Data([1]), ownerUserID: GameFixture.me, roundID: GameFixture.roundID)
            store.saveRescuedDrawing(Data([2]), ownerUserID: GameFixture.me)
            store.saveDownloadedDrawing(Data([3]), mediaAssetID: asset)
            store.saveLiveSnapshot(Data([4]), ownerUserID: GameFixture.me, roundID: GameFixture.roundID)
        }

        // A person keeps one live snapshot. A newer round's replaces it.
        store.saveLiveSnapshot(Data([5]), ownerUserID: GameFixture.me, roundID: GameFixture.nextRoundID)
        fill()
        #expect(store.liveSnapshot(ownerUserID: GameFixture.me, roundID: GameFixture.nextRoundID) == nil)
        #expect(store.liveSnapshot(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == Data([4]))
        store.purge(for: .relationshipAccessHidden)

        #expect(store.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == Data([1]))
        #expect(store.rescuedDrawing(ownerUserID: GameFixture.me) == Data([2]))
        #expect(store.downloadedDrawing(mediaAssetID: asset) == nil)
        #expect(store.liveSnapshot(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == nil)

        // Signing out and a permanent loss remove everything.
        for scope in [LocalPrivacyPurgeScope.departingUser, .relationshipContentPurged(clearAccessSnapshot: true)] {
            fill()
            store.purge(for: scope)
            #expect(store.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == nil)
            #expect(store.rescuedDrawing(ownerUserID: GameFixture.me) == nil)
            #expect(store.downloadedDrawing(mediaAssetID: asset) == nil)
            #expect(store.liveSnapshot(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == nil)
        }
    }

    // MARK: A refused word

    @Test func aRefusedWordKeepsTheQueuedDrawingInsteadOfSendingItToAMissingRound() async throws {
        let pickOperation = operation(1)
        try await enqueue(.pickDrawWord, pick(), pickOperation)
        try await enqueue(.submitGameDrawing, drawing(), operation(2))
        environment.gateway.setPickError(.server(code: "23514", message: "word choice is out of date"))
        let handler = PickDrawWordPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )

        let result = try await handler.send(
            try snapshot(.pickDrawWord, pick(), operation: pickOperation),
            context: syncContext(environment.pending)
        )

        guard case .terminalFailure = result else {
            Issue.record("Expected a terminal failure, got \(result)")
            return
        }
        #expect(environment.drawingStore.rescuedDrawing(ownerUserID: GameFixture.me) == Data([1, 2, 3]))
        #expect(await environment.queued(.submitGameDrawing).isEmpty)
        #expect(environment.transfer.uploads.isEmpty)
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me) == [.wordRejectedDrawingKept])
    }

    @Test func aRefusedWordKeepsTheDraftOfADrawerWhoIsStillDrawing() async throws {
        environment.drawingStore.saveDraft(Data([9]), ownerUserID: GameFixture.me, roundID: GameFixture.roundID)
        environment.gateway.setPickError(.server(code: "23514", message: "word choice is out of date"))
        let handler = PickDrawWordPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )

        _ = try await handler.send(try snapshot(.pickDrawWord, pick()), context: syncContext(environment.pending))

        #expect(environment.drawingStore.rescuedDrawing(ownerUserID: GameFixture.me) == Data([9]))
        #expect(environment.drawingStore.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == nil)
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me) == [.wordRejectedDrawingKept])
    }

    // MARK: Guess order

    private func guessHandler() -> SubmitGameGuessPendingOperationHandler {
        SubmitGameGuessPendingOperationHandler(gateway: environment.gateway, cache: environment.cache)
    }

    @Test func aGuessWaitsForTheEarlierGuessOfTheSameRound() async throws {
        let first = guess("cat")
        let second = guess("umbrella", correct: true)
        try await enqueue(.submitGameGuess, first, operation(1))
        try await enqueue(.submitGameGuess, second, operation(2))
        let context = syncContext(environment.pending)

        let waiting = try await guessHandler().send(
            try snapshot(.submitGameGuess, second, operation: operation(2)),
            context: context
        )
        #expect(waiting == .retry(after: nil))
        #expect(environment.gateway.guesses.isEmpty)

        let sent = try await guessHandler().send(
            try snapshot(.submitGameGuess, first, operation: operation(1)),
            context: context
        )
        #expect(sent == .succeeded)
        #expect(environment.gateway.guesses == ["cat"])
    }

    @Test func showMeWaitsForEarlierGuessesButAGuessInAnotherRoundDoesNot() async throws {
        let earlier = guess("cat")
        try await enqueue(.submitGameGuess, earlier, operation(1))
        let giveUp = GameGiveUpPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now)
        let giveUpHandler = GiveUpGameRoundPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache
        )
        let context = syncContext(environment.pending)

        let waiting = try await giveUpHandler.send(
            try snapshot(.giveUpGameRound, giveUp, operation: operation(2)),
            context: context
        )
        #expect(waiting == .retry(after: nil))

        let otherRound = guess("dog", roundID: UUID())
        let sent = try await guessHandler().send(
            try snapshot(.submitGameGuess, otherRound, operation: operation(3)),
            context: context
        )
        #expect(sent == .succeeded)
        #expect(environment.gateway.guesses == ["dog"])
    }
}
