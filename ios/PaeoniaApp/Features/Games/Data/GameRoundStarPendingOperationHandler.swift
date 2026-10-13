import Foundation

/// Sends a star or an unstar for a finished round. The server sets the value it
/// is given, so sending the same write twice changes nothing, and the writes of
/// one round go in the order they were made, which makes the last one win.
///
/// It waits for this person's guesses and give up of the round, because the
/// server stars only a finished round. A refusal that a retry can't fix drops
/// the write without a notice: the star then shows the server's value again.
struct SetGameRoundStarPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .setGameRoundStar

    private let gateway: any GamesGateway
    private let cache: any GamesCaching

    init(gateway: any GamesGateway, cache: any GamesCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameStarPayload.self, from: data)
        else {
            return .terminalFailure("Missing star payload")
        }
        // An earlier star of the same round goes first, so the last write wins.
        let earlierKinds: [SyncPendingOperationKind] = [.submitGameGuess, .giveUpGameRound, .setGameRoundStar]
        if try await hasEarlierGameMove(in: payload.roundID, before: operation, context: context, kinds: earlierKinds) {
            return .retry(after: nil)
        }
        do {
            let result = try await gateway.setRoundStar(roundID: payload.roundID, starred: payload.starred)
            // Kept before the write leaves the queue, so the star never flips back
            // to the server's old value in between.
            await cache.saveStars([payload.roundID: result.starred], ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}
