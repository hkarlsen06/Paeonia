import Foundation

/// Which server refusals of a board game action a retry can never fix. The same
/// rule as `GameServerRejection`, with `40001 the game has changed`.
nonisolated enum BoardGameServerRejection {
    /// `40001`: the game is not as the action saw it. Another version is
    /// current, or the game is over.
    static func isStale(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return code == "40001"
    }

    /// A stale game, a check that failed (`23514`, such as a move the rules
    /// refuse), or a move out of turn (`42501 it is not your turn`). Access
    /// errors keep retrying, because access can come back.
    static func isPermanent(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        switch code {
        case "40001", "23514":
            return true
        case "42501":
            return message.contains("not your turn")
        default:
            return false
        }
    }

    /// The server answered, and the answer is not one a retry can change.
    /// Offline and sign-in problems are not in this group: they come back as
    /// other errors or as `42501` and `55P03`, which keep retrying.
    static func isUnexplained(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return code != "42501" && code != "55P03" && !isPermanent(error) && !GameServerRejection.isAlreadyDone(error)
    }

    /// Whether to drop the action now: a permanent refusal, or the
    /// `GameServerRejection.unexplainedRefusalLimit`th unexplained one. Only
    /// unexplained refusals count, kept in `cache`, so offline tries and waits
    /// behind an earlier action never use up the tries.
    static func shouldDrop(
        _ error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any BoardGamesCaching
    ) async -> Bool {
        if isPermanent(error) { return true }
        guard isUnexplained(error) else { return false }
        let refusals = await cache.recordUnexplainedRefusal(
            operationID: operation.operation.id,
            ownerUserID: operation.ownerUserID
        )
        return refusals >= GameServerRejection.unexplainedRefusalLimit
    }
}

/// The server took a move or a rematch. Reads the server's games before the
/// action leaves the queue, so the board keeps showing it while the live feed
/// catches up instead of falling back to the state from before it. When the
/// read fails, the action stays in the queue: the next try replays it, which the
/// server answers from its record of the operation, and reads again. That try
/// comes after 2 to 15 seconds (`readAfterMoveRetryPolicy`).
func readBoardGamesAfterAcceptedAction(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any BoardGamesGateway,
    cache: any BoardGamesCaching
) async -> PendingSyncOperationSendResult {
    do {
        _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
        return .succeeded
    } catch {
        return .retry(after: readAfterMoveRetryPolicy.nextRetryDate(
            attemptNumber: operation.attemptCount + 1,
            now: Date()
        ))
    }
}

/// Moves and rematches of one kind of game go in the order they were made, by
/// the phone's own sequence, which a clock change can't reorder. A
/// move that left before its predecessor would be refused as stale, and a
/// rematch that left before the move that ended the game would be refused as
/// too early. Other kinds of game do not wait for each other.
func hasEarlierBoardGameAction(
    of kind: GameKind,
    before operation: PendingSyncOperationSnapshot,
    context: SyncContext
) async throws -> Bool {
    struct Action: Decodable {
        let kind: GameKind
    }
    let order = { (snapshot: PendingSyncOperationSnapshot) in
        snapshot.operation.clientSequence
    }
    for pendingKind in [SyncPendingOperationKind.boardGameMove, .boardGameRematch] {
        let earlier = try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: operation.ownerUserID, kind: pendingKind)
            .contains { other in
                other.operation.id != operation.operation.id
                    && order(other) < order(operation)
                    && other.requestData.flatMap({ try? JSONDecoder().decode(Action.self, from: $0) })?.kind == kind
            }
        if earlier {
            return true
        }
    }
    return false
}

// MARK: - Make a move

/// `boardGames:make_move`. A move the server refuses for good is dropped and
/// the person hears about it, so the board can show the server's state again.
struct BoardGameMovePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .boardGameMove

    private let gateway: any BoardGamesGateway
    private let cache: any BoardGamesCaching

    init(gateway: any BoardGamesGateway, cache: any BoardGamesCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(BoardGameMovePayload.self, from: data)
        else {
            return .terminalFailure("Missing board game move payload")
        }
        if try await hasEarlierBoardGameAction(of: payload.kind, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            let answer = try await gateway.makeMove(payload, operation: operation.operation)
            await cache.saveGame(answer, ownerUserID: operation.ownerUserID)
            return await readBoardGamesAfterAcceptedAction(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await readBoardGamesAfterAcceptedAction(operation, gateway: gateway, cache: cache)
            }
            guard await BoardGameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            // The game moved on without this phone hearing, or the board was
            // wrong. One read puts the server's game back on the board now. The
            // live feed covers a read that fails.
            _ = try? await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
            await cache.recordNotice(.moveRejected(payload.kind), ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}

// MARK: - Play again

/// `boardGames:start_rematch`. When the game has changed since, someone already
/// started the next one (or the game is gone), so the rematch counts as done
/// and the person sees the new game. A rematch for a game that is not over is
/// dropped without a word, because the board never offered it.
struct BoardGameRematchPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .boardGameRematch

    private let gateway: any BoardGamesGateway
    private let cache: any BoardGamesCaching

    init(gateway: any BoardGamesGateway, cache: any BoardGamesCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(BoardGameRematchPayload.self, from: data)
        else {
            return .terminalFailure("Missing board game rematch payload")
        }
        if try await hasEarlierBoardGameAction(of: payload.kind, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            let answer = try await gateway.startRematch(payload, operation: operation.operation)
            await cache.saveGame(answer, ownerUserID: operation.ownerUserID)
            return await readBoardGamesAfterAcceptedAction(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) || BoardGameServerRejection.isStale(error) {
                return await readBoardGamesAfterAcceptedAction(operation, gateway: gateway, cache: cache)
            }
            guard await BoardGameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            return .terminalFailure(error.description)
        }
    }
}
