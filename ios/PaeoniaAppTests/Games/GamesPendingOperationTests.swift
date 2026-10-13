import Foundation
import Testing
@testable import PaeoniaApp

/// How queued Games moves reach the server: the order they go in, what a refusal
/// does, and that nothing the person drew is lost.
@MainActor
struct GamesPendingOperationTests {
    private let environment = GamesTestEnvironment(state: nil)

    init() {
        // The server answers the read that follows each move it takes.
        environment.gateway.setStateToLoad(
            GameFixture.state(settings: GameFixture.settings(), game: GameFixture.game(state: .guessing, turn: GameFixture.me))
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
            reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 10),
            finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 11)
        )
    }

    private func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: GameFixture.now),
                operationKind: kind,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    private func drawingHandler() -> SubmitGameDrawingPendingOperationHandler {
        SubmitGameDrawingPendingOperationHandler(
            gateway: environment.gateway,
            transfer: environment.transfer,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )
    }

    // MARK: Ordering

    @Test func theDrawingWaitsForTheWordPickOfItsRound() async throws {
        try await enqueue(.pickDrawWord, pick(), sequence: 1)
        let operation = try snapshot(.submitGameDrawing, drawing(), operation: SyncClientOperation(clientID: UUID(), clientSequence: 2))

        let waiting = try await drawingHandler().send(operation, context: syncContext(environment.pending))

        #expect(waiting == .retry(after: nil))
        #expect(environment.transfer.uploads.isEmpty)
        #expect(environment.gateway.submittedDrawings.isEmpty)
    }

    @Test func onceThePickHasLandedTheDrawingUploadsAndIsSubmitted() async throws {
        let operation = try snapshot(.submitGameDrawing, drawing(), operation: SyncClientOperation(clientID: UUID(), clientSequence: 2))

        let result = try await drawingHandler().send(operation, context: syncContext(environment.pending))

        #expect(result == .succeeded)
        #expect(environment.transfer.uploads.map(\.roundID) == [GameFixture.roundID])
        let submitted = environment.gateway.submittedDrawings
        #expect(submitted.map(\.roundID) == [GameFixture.roundID])
        #expect(submitted.map(\.assetID) == [GameFixture.assetID])
    }

    @Test func aPickForAnotherRoundDoesNotHoldTheDrawingBack() async throws {
        try await enqueue(.pickDrawWord, pick(roundID: UUID()), sequence: 1)
        let operation = try snapshot(.submitGameDrawing, drawing(), operation: SyncClientOperation(clientID: UUID(), clientSequence: 2))

        let result = try await drawingHandler().send(operation, context: syncContext(environment.pending))

        #expect(result == .succeeded)
    }

    @Test func thePickWaitsForTheGuessThatGivesTheTurn() async throws {
        let guess = GameGuessPayload(
            id: UUID(),
            roundID: UUID(),
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now
        )
        try await enqueue(.submitGameGuess, guess, sequence: 1)
        let handler = PickDrawWordPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )
        let operation = try snapshot(.pickDrawWord, pick(), operation: SyncClientOperation(clientID: UUID(), clientSequence: 2, localCreatedAt: GameFixture.now))

        let waiting = try await handler.send(operation, context: syncContext(environment.pending))

        #expect(waiting == .retry(after: nil))
        #expect(environment.gateway.pickedWords.isEmpty)
    }

    @Test func aPickWithNothingAheadIsSent() async throws {
        let handler = PickDrawWordPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )

        let result = try await handler.send(try snapshot(.pickDrawWord, pick()), context: syncContext(environment.pending))

        #expect(result == .succeeded)
        #expect(environment.gateway.pickedWords.map(\.word) == ["umbrella"])
    }

    // MARK: Refusals

    @Test func aWordThatIsNoLongerOnOfferStopsTheRetryAndTellsThePerson() async throws {
        environment.gateway.setPickError(.server(code: "23514", message: "word choice is out of date"))
        let handler = PickDrawWordPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )

        let result = try await handler.send(try snapshot(.pickDrawWord, pick()), context: syncContext(environment.pending))

        guard case .terminalFailure = result else {
            Issue.record("Expected a terminal failure, got \(result)")
            return
        }
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me) == [.wordRejected])
    }

    @Test func aNetworkErrorOrLostAccessKeepsRetrying() async {
        environment.gateway.setPickError(.server(code: "42501", message: "active entitled game access is required"))
        let handler = PickDrawWordPendingOperationHandler(
            gateway: environment.gateway,
            cache: environment.cache,
            drawingStore: environment.drawingStore
        )

        do {
            _ = try await handler.send(try snapshot(.pickDrawWord, pick()), context: syncContext(environment.pending))
            Issue.record("Expected the error to reach the drain, which retries")
        } catch {
            #expect(error is PaeoniaConvexError)
        }
    }

    @Test func aRefusedDrawingGoesBackOnTheCanvasAsADraft() async throws {
        environment.gateway.setSubmitError(.server(code: "42501", message: "only the drawer can send the drawing"))

        let result = try await drawingHandler().send(
            try snapshot(.submitGameDrawing, drawing()),
            context: syncContext(environment.pending)
        )

        guard case .terminalFailure = result else {
            Issue.record("Expected a terminal failure, got \(result)")
            return
        }
        #expect(environment.drawingStore.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == Data([1, 2, 3]))
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me) == [.drawingRejected])
    }

    @Test func aDrawingTheServerAlreadyHasCountsAsSent() async throws {
        environment.gateway.setSubmitError(.server(code: "23505", message: "the drawing for this round was already sent"))

        let result = try await drawingHandler().send(
            try snapshot(.submitGameDrawing, drawing()),
            context: syncContext(environment.pending)
        )

        #expect(result == .succeeded)
        #expect(environment.drawingStore.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) == nil)
    }

    // MARK: The queue

    @Test func theQueueReadsBackWhatIsWaiting() async throws {
        try await enqueue(.pickDrawWord, pick(), sequence: 1)
        try await enqueue(.submitGameDrawing, drawing(), sequence: 2)
        try await enqueue(
            .submitGameGuess,
            GameGuessPayload(id: UUID(), roundID: GameFixture.roundID, guess: "cat", isCorrect: false, createdAt: GameFixture.now),
            sequence: 3
        )
        try await enqueue(.giveUpGameRound, GameGiveUpPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now), sequence: 4)

        let work = try #require(await DrawAndGuessPendingWork.load(from: environment.pending, ownerUserID: GameFixture.me))

        #expect(work.pick?.word == "umbrella")
        #expect(work.hasDrawing(roundID: GameFixture.roundID))
        #expect(work.guesses(roundID: GameFixture.roundID).map(\.guess) == ["cat"])
        #expect(work.hasGiveUp(roundID: GameFixture.roundID))
        #expect(work.hasMoveWaiting)
        #expect(work.reaction(roundID: GameFixture.roundID) == nil)
        #expect(!work.hasResultSeen(roundID: GameFixture.roundID))
    }

    @Test func reactionsAndSeenMarksAreReadBackButAreNotMoves() async throws {
        try await enqueue(
            .setGameRoundReaction,
            GameReactionPayload(roundID: GameFixture.roundID, reaction: .love, createdAt: GameFixture.now),
            sequence: 1
        )
        try await enqueue(
            .setGameRoundReaction,
            GameReactionPayload(roundID: GameFixture.roundID, reaction: nil, createdAt: GameFixture.now),
            sequence: 2
        )
        try await enqueue(
            .markGameRoundResultSeen,
            GameResultSeenPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now),
            sequence: 3
        )

        let work = try #require(await DrawAndGuessPendingWork.load(from: environment.pending, ownerUserID: GameFixture.me))

        // The last reaction made wins, and a cleared one is a reaction too.
        let reaction = try #require(work.reaction(roundID: GameFixture.roundID))
        #expect(reaction == nil)
        #expect(work.reaction(roundID: UUID()) == nil)
        #expect(work.hasResultSeen(roundID: GameFixture.roundID))
        #expect(!work.hasMoveWaiting)
        #expect(!work.isEmpty)
    }
}
