import Foundation

// How the queued Exquisite corpse writes reach the server. They follow the Draw &
// Guess handlers (`GamesPendingOperationHandlers.swift`): the refusal counting,
// the renewal of an upload the server deleted, and the read of the server's
// state before an accepted move leaves the queue.

// MARK: - Send a part

/// Uploads a part's drawing and, for the head and the body, its strip, then
/// submits the part. Each upload keeps its own reserve and finalize operations
/// in the payload, so a retry replays the same requests and never uploads twice.
///
/// A refusal a retry can't fix puts the drawing back on the canvas as the draft
/// of that part, with a notice, so nothing the person drew is lost.
struct ExquisiteCorpseSubmitPartHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .exquisiteCorpseSubmitPart

    private static let parentKind = "exquisite_corpse_part"
    private static let drawingPurpose = "exquisite_corpse_drawing"
    private static let stripPurpose = "exquisite_corpse_strip"

    private let gateway: any ExquisiteCorpseGateway
    private let transfer: any GameDrawingTransferring
    private let cache: any ExquisiteCorpseCaching
    private let drawingStore: any GameDrawingStoring

    init(
        gateway: any ExquisiteCorpseGateway,
        transfer: any GameDrawingTransferring,
        cache: any ExquisiteCorpseCaching,
        drawingStore: any GameDrawingStoring
    ) {
        self.gateway = gateway
        self.transfer = transfer
        self.cache = cache
        self.drawingStore = drawingStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(ExquisiteCorpseSubmitPartPayload.self, from: data)
        else {
            return .terminalFailure("Missing part payload")
        }

        do {
            let drawingAssetID = try await upload(payload.drawing, of: payload, purpose: Self.drawingPurpose)
            // Kept as the server's copy, so the reveal never has to download the
            // drawer's own part, also after a relaunch while offline.
            drawingStore.saveDownloadedDrawing(payload.drawing.data, mediaAssetID: drawingAssetID)
            var stripAssetID: UUID?
            if let strip = payload.strip {
                stripAssetID = try await upload(strip, of: payload, purpose: Self.stripPurpose)
            }
            _ = try await gateway.submitExquisiteCorpsePart(
                payload,
                drawingAssetID: drawingAssetID,
                stripAssetID: stripAssetID,
                operation: operation.operation
            )
            return await readExquisiteCorpseStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isUploadGone(error) || ExquisiteCorpseRefusal.isExpiredUpload(error),
               GameServerRejection.mayRenewUpload(renewedAt: payload.renewedAt) {
                return try await sendWithNewUpload(payload, replacing: operation, context: context)
            }
            // A retry of this send gets the server's stored answer, never `23505`. So
            // `23505` means another send took this part or figure, such as the same
            // turn sent from this person's other phone, and this drawing never went out.
            if !GameServerRejection.isAlreadyDone(error) {
                guard await shouldDrop(error, of: operation, cache: cache) else { throw error }
            }
            return await putBack(payload, of: operation, refusedFor: error)
        }
    }

    /// Nothing the person drew is lost: the drawing goes back on the canvas of
    /// its part, or of this person's next part when its turn has moved on.
    private func putBack(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        of operation: PendingSyncOperationSnapshot,
        refusedFor error: PaeoniaConvexError
    ) async -> PendingSyncOperationSendResult {
        drawingStore.saveDraft(payload.drawing.data, ownerUserID: operation.ownerUserID, roundID: payload.partID)
        if ExquisiteCorpseRefusal.isUnknownIdea(error) {
            await cache.saveIdea(nil, partID: payload.partID, ownerUserID: operation.ownerUserID)
        }
        await cache.recordNotice(.partRejected, ownerUserID: operation.ownerUserID)
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure(error.description)
    }

    private func upload(
        _ file: ExquisiteCorpseQueuedUpload,
        of payload: ExquisiteCorpseSubmitPartPayload,
        purpose: String
    ) async throws -> UUID {
        try await transfer.uploadDrawing(
            file.data,
            parent: GameUploadParent(
                kind: Self.parentKind,
                id: payload.partID,
                purpose: purpose,
                gameID: payload.gameID
            ),
            coupleID: payload.coupleID,
            reserveOperation: file.reserveOperation,
            finalizeOperation: file.finalizeOperation
        )
    }

    /// Queues the same part with new upload operations, so the kept bytes upload
    /// again, and retires this write. The new one is saved first, so the drawing
    /// is never only in a write that stopped.
    private func sendWithNewUpload(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        replacing operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        try await context.pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: operation.ownerUserID,
                // Same place in the order as the write it replaces.
                operation: SyncClientOperation(
                    clientID: operation.operation.clientID,
                    clientSequence: operation.operation.clientSequence,
                    localCreatedAt: operation.operation.localCreatedAt
                ),
                operationKind: .exquisiteCorpseSubmitPart,
                idempotencyScope: operation.idempotencyScope,
                requestData: try JSONEncoder().encode(payload.withNewUploads(renewedAt: Date()))
            )
        )
        return .terminalFailure("The upload expired. The part was queued again with a new upload.")
    }
}

// MARK: - Move past the reveal

/// Tells the server this person moved past a finished figure's reveal. It waits
/// for this person's queued part of the figure, because the server marks only a
/// finished figure. The server keeps the first time, so a retry is safe. Only a
/// refusal a retry can never fix drops it, without a notice, because the server's
/// state is what the screens show. Any other error keeps it in the queue.
struct ExquisiteCorpseRevealSeenHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .exquisiteCorpseRevealSeen

    private let gateway: any ExquisiteCorpseGateway
    private let cache: any ExquisiteCorpseCaching

    init(gateway: any ExquisiteCorpseGateway, cache: any ExquisiteCorpseCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(ExquisiteCorpseRevealSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing reveal seen payload")
        }
        let hasQueuedPart = try await hasQueuedWrite(
            .exquisiteCorpseSubmitPart,
            forFigure: payload.figureID,
            of: operation,
            context: context
        )
        if hasQueuedPart {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.markExquisiteCorpseRevealSeen(figureID: payload.figureID)
            return await readExquisiteCorpseStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            guard GameServerRejection.isPermanent(error) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}

// MARK: - Star

/// Sends a star or an unstar for a finished figure. The server sets the value it
/// is given, so sending the same write twice changes nothing, and the writes of
/// one figure go in the order they were made, which makes the last one win.
///
/// It also waits for this person's queued part of the figure, because the server
/// stars only a finished figure. A refusal that a retry can't fix drops the
/// write without a notice: the star then shows the server's value again.
struct ExquisiteCorpseStarHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .exquisiteCorpseStar

    private let gateway: any ExquisiteCorpseGateway
    private let cache: any ExquisiteCorpseCaching

    init(gateway: any ExquisiteCorpseGateway, cache: any ExquisiteCorpseCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(ExquisiteCorpseStarPayload.self, from: data)
        else {
            return .terminalFailure("Missing star payload")
        }
        // An earlier star of the same figure goes first, so the last write wins.
        let hasQueuedPart = try await hasQueuedWrite(
            .exquisiteCorpseSubmitPart,
            forFigure: payload.figureID,
            of: operation,
            context: context
        )
        let hasEarlierStar = try await hasQueuedWrite(
            .exquisiteCorpseStar,
            forFigure: payload.figureID,
            of: operation,
            earlierOnly: true,
            context: context
        )
        if hasQueuedPart || hasEarlierStar {
            return .retry(after: nil)
        }
        do {
            let result = try await gateway.setExquisiteCorpseStar(figureID: payload.figureID, starred: payload.starred)
            // Kept before the write leaves the queue, so the star never flips back
            // to the server's old value in between.
            await cache.saveStars([payload.figureID: result.starred], ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            guard await shouldDrop(error, of: operation, cache: cache) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}

// MARK: - Shared by the handlers

nonisolated private enum ExquisiteCorpseRefusal {
    /// `submit_exquisite_corpse_part` says an argument is wrong (`22023`), such as
    /// an idea it does not know. The same request is wrong again, so counting tries
    /// would only delay the notice. The media calls answer `22023` too, for an
    /// upload that ran out of time, and those are not this.
    static func isInvalidArgument(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error, code == "22023" else { return false }
        return ["part index", "need a strip", "take no strip", "idea"].contains { message.contains($0) }
    }

    /// The upload's reservation ran out while the bytes were on their way. A new
    /// upload fixes it.
    static func isExpiredUpload(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        return code == "22023" && message.contains("media upload reservation is expired")
    }

    static func isUnknownIdea(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        return code == "22023" && message.contains("idea")
    }
}

/// Whether to drop the write now: a refusal a retry can never fix, or the
/// `GameServerRejection.unexplainedRefusalLimit`th unexplained one. Offline tries
/// and waits never count.
private func shouldDrop(
    _ error: PaeoniaConvexError,
    of operation: PendingSyncOperationSnapshot,
    cache: any ExquisiteCorpseCaching
) async -> Bool {
    if ExquisiteCorpseRefusal.isInvalidArgument(error) {
        return true
    }
    return await GameServerRejection.shouldDrop(error, of: operation) { operationID, ownerUserID in
        await cache.recordUnexplainedRefusal(operationID: operationID, ownerUserID: ownerUserID)
    }
}

/// The server took a move. Reads its state before the move leaves the queue, as
/// Draw & Guess does, so the screen keeps showing the move while the live feed
/// catches up.
private func readExquisiteCorpseStateAfterAcceptedMove(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any ExquisiteCorpseGateway,
    cache: any ExquisiteCorpseCaching
) async -> PendingSyncOperationSendResult {
    await readStateAfterAcceptedMove(operation) {
        _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
    }
}

nonisolated private struct QueuedFigureWrite: Decodable {
    let figureID: UUID
}

/// Whether this person has a write of `kind` for the figure that has not reached
/// the server. With `earlierOnly`, only one queued before `operation` counts.
private func hasQueuedWrite(
    _ kind: SyncPendingOperationKind,
    forFigure figureID: UUID,
    of operation: PendingSyncOperationSnapshot,
    earlierOnly: Bool = false,
    context: SyncContext
) async throws -> Bool {
    let order = { (snapshot: PendingSyncOperationSnapshot) in
        (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
    }
    let decoder = JSONDecoder()
    let figureOf = { (snapshot: PendingSyncOperationSnapshot) in
        snapshot.requestData.flatMap { try? decoder.decode(QueuedFigureWrite.self, from: $0) }?.figureID
    }
    return try await context.pendingOperationStore
        .inFlightOperations(ownerUserID: operation.ownerUserID, kind: kind)
        .contains { other in
            guard other.operation.id != operation.operation.id, figureOf(other) == figureID else { return false }
            return !earlierOnly || order(other) < order(operation)
        }
}
