import Foundation

struct PiccantePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind
    let gateway: any PiccanteGateway
    let cache: any PiccanteCaching
    func send(_ operation: PendingSyncOperationSnapshot, context: SyncContext) async throws
        -> PendingSyncOperationSendResult
    {
        guard let data = operation.requestData,
            let move = try? JSONDecoder().decode(PiccanteMove.self, from: data)
        else {
            return .terminalFailure("Missing Piccante move")
        }
        for kind in PiccanteAction.allCases.map(\.pendingKind) {
            let earlier = try await context.pendingOperationStore.inFlightOperations(
                ownerUserID: operation.ownerUserID, kind: kind)
            if earlier.contains(where: {
                $0.operation.id != operation.operation.id
                    && $0.operation.clientSequence < operation.operation.clientSequence
            }) {
                return .retry(after: nil)
            }
        }
        do {
            let state = try await gateway.sendPiccante(move, operation: operation.operation)
            await cache.saveState(state, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            let stale = BoardGameServerRejection.isStale(error)
            if stale, move.action == .rematch {
                return await readAfterRematch(operation, move: move)
            }
            if !stale {
                guard await GameServerRejection.shouldDrop(
                    error, of: operation,
                    recordRefusal: { id, owner in
                        await cache.recordRefusal(operationID: id, ownerUserID: owner)
                    })
                else { throw error }
            }
            if let state = try? await gateway.loadPiccante() {
                await cache.saveState(state, ownerUserID: operation.ownerUserID)
            }
            await cache.refuse(move, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }

    private func readAfterRematch(_ operation: PendingSyncOperationSnapshot, move: PiccanteMove) async
        -> PendingSyncOperationSendResult
    {
        await readStateAfterAcceptedMove(operation) {
            var state = try await gateway.loadPiccante()
            if let current = state.game, current.gameNumber > move.gameNumber {
                let seen = PiccanteMove(
                    action: .seen, gameID: move.gameID, gameNumber: move.gameNumber,
                    expectedVersion: current.version)
                let seenOperation = await MainActor.run { SyncClientOperationFactory.shared.makeOperation() }
                state = try await gateway.sendPiccante(seen, operation: seenOperation)
            }
            await cache.saveState(state, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        }
    }
}

nonisolated extension PiccanteAction {
    var pendingKind: SyncPendingOperationKind {
        switch self {
        case .choose: .piccanteChoose
        case .hide: .piccanteHide
        case .bite: .piccanteBite
        case .sniff: .piccanteSniff
        case .rematch: .piccanteRematch
        case .seen: .piccanteSeen
        }
    }
}
