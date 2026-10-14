import Foundation
import Testing
@testable import PaeoniaApp

/// How queued board game actions reach the server: the order they go in, what a
/// refusal does, and that the board keeps the server's answer.
@MainActor
struct BoardGamePendingOperationTests {
    private typealias Fixture = BoardGameDataFixture

    private let me = Fixture.me
    private let gateway = ScriptedBoardGamesGateway()
    private let cache: InMemoryBoardGamesCache
    private let pending = InMemoryPendingSyncOperationRepository()
    /// The game on this phone before the action. The server holds it after one move.
    private let game = Fixture.game()

    init() {
        cache = InMemoryBoardGamesCache(state: Fixture.state(game), ownerUserID: Fixture.me)
        gateway.setStateToLoad(Fixture.state(Fixture.game(moves: [3])))
    }

    private var moveHandler: BoardGameMovePendingOperationHandler {
        BoardGameMovePendingOperationHandler(gateway: gateway, cache: cache)
    }

    private var rematchHandler: BoardGameRematchPendingOperationHandler {
        BoardGameRematchPendingOperationHandler(gateway: gateway, cache: cache)
    }

    /// Sends the move as the drain does. Pass the same operation again to try
    /// the same queued write again.
    private func sendMove(
        as operation: SyncClientOperation = Fixture.operation(sequence: 1)
    ) async throws -> PendingSyncOperationSendResult {
        let queued = try snapshot(.boardGameMove, Fixture.move(3, on: game), operation: operation)
        return try await moveHandler.send(queued, context: syncContext(pending))
    }

    private func sendRematch(
        as operation: SyncClientOperation = Fixture.operation(sequence: 1)
    ) async throws -> PendingSyncOperationSendResult {
        let queued = try snapshot(.boardGameRematch, Fixture.rematch(of: game), operation: operation)
        return try await rematchHandler.send(queued, context: syncContext(pending))
    }

    /// Puts an action in the pending operations and returns its operation.
    @discardableResult
    private func enqueue(_ action: BoardGamePendingAction, sequence: Int64) async throws -> SyncClientOperation {
        let operation = Fixture.operation(sequence: sequence)
        try await pending.enqueue(BoardGamePendingWork.request(for: action, ownerUserID: me, operation: operation))
        return operation
    }

    private func expectTerminalFailure(_ result: PendingSyncOperationSendResult) {
        guard case .terminalFailure = result else {
            Issue.record("Expected a terminal failure, got \(result)")
            return
        }
    }

    private func notices() async -> [BoardGameStoredNotice] {
        await cache.takeNotices(kind: .connectFour, ownerUserID: me)
    }

    // MARK: A move the server takes

    @Test func aMoveIsReadBackBeforeItLeavesTheQueue() async throws {
        // The read-back carries a game the answer to the move does not.
        let dotsAndBoxes = Fixture.game(kind: .dotsAndBoxes, id: Fixture.otherGameID)
        gateway.setStateToLoad(Fixture.state(Fixture.game(moves: [3]), dotsAndBoxes))

        let result = try await sendMove()

        #expect(result == .succeeded)
        #expect(gateway.calls == ["makeMove", "loadBoardGames"])
        #expect(gateway.moves == [Fixture.move(3, on: game)])
        let state = await cache.document(ownerUserID: me).state
        #expect(state?.game(.connectFour)?.moves == [3])
        #expect(state?.game(.dotsAndBoxes) == dotsAndBoxes)
        #expect(await notices().isEmpty)
    }

    @Test func aFailedReadBackKeepsTheMoveInTheQueueAndTheAnswerOnTheBoard() async throws {
        gateway.fail("loadBoardGames")

        let result = try await sendMove()

        guard case let .retry(after: date?) = result else {
            Issue.record("Expected a retry with a date, got \(result)")
            return
        }
        // 2 seconds after the first try, not the usual minute.
        #expect((1.0...3.0).contains(date.timeIntervalSinceNow))
        #expect(await cache.document(ownerUserID: me).state?.game(.connectFour)?.moves == [3])
        #expect(await notices().isEmpty)
    }

    @Test func theReplayOfAMoveTheServerAlreadyHasCountsAsSent() async throws {
        gateway.setMoveError(.server(code: "23505", message: "the operation was already used for another request"))

        let result = try await sendMove()

        #expect(result == .succeeded)
        #expect(gateway.calls == ["makeMove", "loadBoardGames"])
        #expect(await notices().isEmpty)
    }

    // MARK: A move the server refuses

    @Test(arguments: [
        PaeoniaConvexError.server(code: "40001", message: "the game has changed"),
        .server(code: "42501", message: "it is not your turn"),
        .server(code: "23514", message: "that move is not allowed"),
        .server(code: "23514", message: "that stake is not allowed")
    ])
    func aMoveRefusedForGoodIsDroppedAndTheBoardHearsAboutIt(error: PaeoniaConvexError) async throws {
        gateway.setMoveError(error)

        let result = try await sendMove()

        expectTerminalFailure(result)
        #expect(await notices() == [.moveRejected(.connectFour)])
    }

    @Test(arguments: [
        PaeoniaConvexError.server(code: "42501", message: "active entitled game access is required"),
        .server(code: "55P03", message: "another request is in progress"),
        .notAuthenticated,
        .http(status: 503, body: "")
    ])
    func aMoveThatMayStillWorkKeepsRetrying(error: PaeoniaConvexError) async throws {
        gateway.setMoveError(error)

        await #expect(throws: PaeoniaConvexError.self) { try await sendMove() }
        #expect(await notices().isEmpty)
    }

    @Test func aMoveThatCouldNotReachTheServerKeepsRetrying() async throws {
        gateway.fail("makeMove")

        await #expect(throws: ScriptedBoardGamesGateway.Failure.self) { try await sendMove() }
        #expect(await notices().isEmpty)
    }

    @Test func aMoveTheServerKeepsRefusingForNoKnownReasonIsDroppedOnTheThirdTry() async throws {
        gateway.setMoveError(.server(code: "XX000", message: "the stored game is not valid"))
        let operation = Fixture.operation(sequence: 1)

        for _ in 1...2 {
            await #expect(throws: PaeoniaConvexError.self) { try await sendMove(as: operation) }
            #expect(await notices().isEmpty)
        }
        let third = try await sendMove(as: operation)

        expectTerminalFailure(third)
        #expect(await notices() == [.moveRejected(.connectFour)])
    }

    @Test func eachMoveCountsItsOwnUnexplainedRefusals() async throws {
        gateway.setMoveError(.server(code: nil, message: "Unknown error"))
        let first = Fixture.operation(sequence: 1)
        let second = Fixture.operation(sequence: 2)

        for operation in [first, second, first, second] {
            await #expect(throws: PaeoniaConvexError.self) { try await sendMove(as: operation) }
        }

        // Two tries each, so neither move has reached the limit of three.
        #expect(await notices().isEmpty)
    }

    @Test func aMoveWithoutItsPayloadIsDropped() async throws {
        let operation = try snapshot(.boardGameMove, ["unrelated": 1])

        let result = try await moveHandler.send(operation, context: syncContext(pending))

        expectTerminalFailure(result)
        #expect(gateway.calls.isEmpty)
    }

    // MARK: Order

    @Test func aMoveWaitsForAnEarlierMoveOfTheSameGame() async throws {
        try await enqueue(.move(Fixture.move(2, on: game)), sequence: 1)

        let result = try await sendMove(as: Fixture.operation(sequence: 2))

        #expect(result == .retry(after: nil))
        #expect(gateway.calls.isEmpty)
    }

    @Test func aMoveWaitsForAnEarlierRematchOfTheSameGame() async throws {
        try await enqueue(.rematch(Fixture.rematch(of: game)), sequence: 1)

        let result = try await sendMove(as: Fixture.operation(sequence: 2))

        #expect(result == .retry(after: nil))
        #expect(gateway.calls.isEmpty)
    }

    @Test func aRematchWaitsForTheMoveThatEndedTheGame() async throws {
        try await enqueue(.move(Fixture.move(2, on: game)), sequence: 1)

        let result = try await sendRematch(as: Fixture.operation(sequence: 2))

        #expect(result == .retry(after: nil))
        #expect(gateway.calls.isEmpty)
    }

    @Test func anEarlierActionOfAnotherKindOfGameHoldsNothingBack() async throws {
        let dotsAndBoxes = Fixture.game(kind: .dotsAndBoxes, id: Fixture.otherGameID)
        try await enqueue(.move(Fixture.move(0, on: dotsAndBoxes)), sequence: 1)

        let result = try await sendMove(as: Fixture.operation(sequence: 2))

        #expect(result == .succeeded)
    }

    @Test func theEarliestActionGoesFirstAndNeverWaitsForItself() async throws {
        let first = try await enqueue(.move(Fixture.move(3, on: game)), sequence: 1)
        try await enqueue(.move(Fixture.move(2, on: game)), sequence: 2)

        let result = try await sendMove(as: first)

        #expect(result == .succeeded)
        #expect(gateway.moves.count == 1)
    }

    @Test func anEarlierMoveThatWasDroppedHoldsNothingBack() async throws {
        let earlier = try await enqueue(.move(Fixture.move(2, on: game)), sequence: 1)
        try await pending.markTerminalFailure(
            clientOperationID: earlier.id,
            errorDescription: "dropped",
            at: Fixture.now
        )

        let result = try await sendMove(as: Fixture.operation(sequence: 2))

        #expect(result == .succeeded)
    }

    // MARK: Play again

    @Test func aRematchIsReadBackBeforeItLeavesTheQueue() async throws {
        let next = Fixture.game(gameNumber: 2, first: Fixture.partner, version: 2)
        gateway.setStateToLoad(Fixture.state(next))

        let result = try await sendRematch()

        #expect(result == .succeeded)
        #expect(gateway.calls == ["startRematch", "loadBoardGames"])
        #expect(gateway.rematches == [Fixture.rematch(of: game)])
        #expect(await cache.document(ownerUserID: me).state?.game(.connectFour)?.gameNumber == 2)
    }

    @Test func aRematchAfterSomeoneElseAlreadyStartedOneSucceedsWithoutAWord() async throws {
        gateway.setRematchError(.server(code: "40001", message: "the game has changed"))
        gateway.setStateToLoad(Fixture.state(Fixture.game(gameNumber: 2, first: Fixture.partner, version: 2)))

        let result = try await sendRematch()

        #expect(result == .succeeded)
        #expect(gateway.calls == ["startRematch", "loadBoardGames"])
        #expect(await cache.document(ownerUserID: me).state?.game(.connectFour)?.gameNumber == 2)
        #expect(await notices().isEmpty)
    }

    @Test func aRematchForAGameThatIsNotOverIsDroppedWithoutAWord() async throws {
        gateway.setRematchError(.server(code: "23514", message: "the game is not over"))

        let result = try await sendRematch()

        expectTerminalFailure(result)
        #expect(await notices().isEmpty)
    }

    @Test func aRematchThatMayStillWorkKeepsRetrying() async throws {
        gateway.setRematchError(.server(code: "42501", message: "active entitled game access is required"))

        await #expect(throws: PaeoniaConvexError.self) { try await sendRematch() }
    }

    @Test func aRematchRefusedForNoKnownReasonIsDroppedOnTheThirdTryWithoutAWord() async throws {
        gateway.setRematchError(.server(code: "XX000", message: "the stored game is not valid"))
        let operation = Fixture.operation(sequence: 1)

        for _ in 1...2 {
            await #expect(throws: PaeoniaConvexError.self) { try await sendRematch(as: operation) }
        }
        let third = try await sendRematch(as: operation)

        expectTerminalFailure(third)
        #expect(await notices().isEmpty)
    }

    @Test func aRematchWithoutItsPayloadIsDropped() async throws {
        let operation = try snapshot(.boardGameRematch, ["unrelated": 1])

        let result = try await rematchHandler.send(operation, context: syncContext(pending))

        expectTerminalFailure(result)
        #expect(gateway.calls.isEmpty)
    }
}
