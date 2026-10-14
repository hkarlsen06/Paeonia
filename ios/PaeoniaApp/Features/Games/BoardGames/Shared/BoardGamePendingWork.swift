import Foundation

/// The queued board game actions of one person that have not reached the server.
/// A move refused for good is no longer in flight, so it drops out of the queue
/// and the board falls back to the server's state.
nonisolated enum BoardGamePendingWork {
    /// Idempotency scope of every action of one kind of game.
    static func scope(for kind: GameKind) -> String {
        "board-game:\(kind.rawValue)"
    }

    /// The in-flight moves and rematches, in the order they were made. Nil when
    /// the queue cannot be read: treating that as an empty queue would make a
    /// queued move look lost. Payloads that fail to decode are skipped.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> [BoardGamePendingAction]? {
        await read(from: store, ownerUserID: ownerUserID)?.map(\.action)
    }

    /// A waiting action of this game was tried again and the attempt failed for
    /// a reason other than having no connection, such as the server refusing
    /// it. The waiting line then says "We couldn't send your move yet" instead
    /// of "Saved on this phone". False when the queue cannot be read.
    static func failedWhileOnline(
        kind: GameKind,
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> Bool {
        await read(from: store, ownerUserID: ownerUserID)?
            .contains { $0.action.kind == kind && $0.failedWhileOnline } ?? false
    }

    /// A waiting action of this game has had a try that did not get through, for
    /// any reason. Until then the action is on its first send, and the screen
    /// says nothing about it being on this phone, so a normal send never flashes
    /// that line. False when the queue cannot be read.
    static func hasFailedAttempt(
        kind: GameKind,
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> Bool {
        await read(from: store, ownerUserID: ownerUserID)?
            .contains { $0.action.kind == kind && $0.hasFailedAttempt } ?? false
    }

    /// The queue entry for an action. `operation` fixes the place in the order.
    static func request(
        for action: BoardGamePendingAction,
        ownerUserID: UUID,
        operation: SyncClientOperation
    ) throws -> PendingSyncOperationRequest {
        let kind: SyncPendingOperationKind
        let data: Data
        switch action {
        case let .move(payload):
            kind = .boardGameMove
            data = try JSONEncoder().encode(payload)
        case let .rematch(payload):
            kind = .boardGameRematch
            data = try JSONEncoder().encode(payload)
        }
        return PendingSyncOperationRequest(
            ownerUserID: ownerUserID,
            operation: operation,
            operationKind: kind,
            idempotencyScope: scope(for: action.kind),
            requestData: data
        )
    }

    // MARK: - Reading the queue

    nonisolated private struct Entry {
        let localCreatedAt: Date
        let clientSequence: Int64
        let action: BoardGamePendingAction
        let failedWhileOnline: Bool
        let hasFailedAttempt: Bool
    }

    /// Both kinds of action in one list, oldest first.
    private static func read(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> [Entry]? {
        let decoder = JSONDecoder()
        let moves: [PendingSyncOperationSnapshot]
        let rematches: [PendingSyncOperationSnapshot]
        do {
            moves = try await store.inFlightOperations(ownerUserID: ownerUserID, kind: .boardGameMove)
            rematches = try await store.inFlightOperations(ownerUserID: ownerUserID, kind: .boardGameRematch)
        } catch {
            return nil
        }
        let moveEntries = moves.compactMap {
            entry(of: $0, decoder: decoder, as: BoardGameMovePayload.self, wrap: BoardGamePendingAction.move)
        }
        let rematchEntries = rematches.compactMap {
            entry(of: $0, decoder: decoder, as: BoardGameRematchPayload.self, wrap: BoardGamePendingAction.rematch)
        }
        return (moveEntries + rematchEntries)
            // The phone's own sequence, which a clock change can't reorder.
            .sorted { $0.clientSequence < $1.clientSequence }
    }

    private static func entry<Payload: Decodable>(
        of operation: PendingSyncOperationSnapshot,
        decoder: JSONDecoder,
        as _: Payload.Type,
        wrap: (Payload) -> BoardGamePendingAction
    ) -> Entry? {
        guard let data = operation.requestData, let payload = try? decoder.decode(Payload.self, from: data) else {
            return nil
        }
        return Entry(
            localCreatedAt: operation.operation.localCreatedAt,
            clientSequence: operation.operation.clientSequence,
            action: wrap(payload),
            failedWhileOnline: operation.failedWhileOnline,
            hasFailedAttempt: operation.hasFailedAttempt
        )
    }
}
