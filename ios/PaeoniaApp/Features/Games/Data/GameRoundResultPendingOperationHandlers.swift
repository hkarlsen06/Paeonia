import Foundation

// What the people do after a round ends: each person moves past the result.

/// Tells the server this person moved past a finished round's result. It waits
/// for the guess or give up that ended the round. The server keeps the first
/// time, so a retry is safe. Only a refusal a retry can never fix drops it.
struct GameResultSeenPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .markGameRoundResultSeen

    private let gateway: any DrawAndGuessGateway
    private let cache: any GamesCaching

    init(gateway: any DrawAndGuessGateway, cache: any GamesCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameResultSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing result seen payload")
        }
        if try await hasEarlierGameMove(in: payload.roundID, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.markRoundResultSeen(roundID: payload.roundID)
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            guard GameServerRejection.isPermanent(error) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}
