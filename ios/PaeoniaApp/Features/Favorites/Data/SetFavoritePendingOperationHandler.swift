import Foundation

/// A rule that holds a favorite back until something else has reached the server. The
/// server saves only a game item that is finished, so the queued moves that finish it go
/// first. A kind without a gate is sent as soon as its turn comes.
nonisolated protocol FavoriteSendGating: Sendable {
    /// True while a write this person queued earlier still has to reach the server.
    func mustWait(
        for target: FavoriteTarget,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool
}

/// Sends a favorite or an unfavorite. The server sets the value it is given, so sending
/// the same write twice changes nothing, and the writes of one item go in the order they
/// were made, which makes the last one win.
///
/// A refusal that a retry can't fix, such as an item that was deleted, drops the write and
/// counts it in the cache. The store tells the person and the star shows the server's value
/// again. Every other failure keeps retrying, so a favorite is never lost silently.
struct SetFavoritePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .setFavorite

    private let gateway: any FavoritesGateway
    private let cache: any FavoritesCaching
    private let gates: [FavoriteKind: any FavoriteSendGating]

    init(
        gateway: any FavoritesGateway,
        cache: any FavoritesCaching,
        gates: [FavoriteKind: any FavoriteSendGating] = [:]
    ) {
        self.gateway = gateway
        self.cache = cache
        self.gates = gates
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(FavoriteWritePayload.self, from: data)
        else {
            return .terminalFailure("Missing favorite payload")
        }
        if try await hasEarlierWrite(of: payload.target, before: operation, context: context) {
            return .retry(after: nil)
        }
        if payload.favorited, let gate = gates[payload.target.kind],
           try await gate.mustWait(for: payload.target, operation: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            try await gateway.setFavorite(payload.target, favorited: payload.favorited)
            // Kept before the write leaves the queue, so the star never flips back to the
            // server's old value in between.
            await cache.apply(
                payload.target,
                favorited: payload.favorited,
                at: payload.createdAt,
                ownerUserID: operation.ownerUserID
            )
            LocalStoreChanges.post(.favorites, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            guard Self.isPermanentRefusal(error) else { throw error }
            await cache.recordRefusal(ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.favorites, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }

    /// `23514`: the item is gone, not finished, or not in this couple. A retry gets the same answer.
    nonisolated static func isPermanentRefusal(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return code == "23514"
    }

    /// Whether this person queued an earlier write for the same item.
    private func hasEarlierWrite(
        of target: FavoriteTarget,
        before operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        let order = { (snapshot: PendingSyncOperationSnapshot) in
            (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
        }
        let decoder = JSONDecoder()
        return try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: operation.ownerUserID, kind: .setFavorite)
            .contains { other in
                guard other.operation.id != operation.operation.id, order(other) < order(operation) else {
                    return false
                }
                let queued = other.requestData.flatMap { try? decoder.decode(FavoriteWritePayload.self, from: $0) }
                return queued?.target == target
            }
    }
}
