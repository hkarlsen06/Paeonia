import Foundation

/// Which server refusals a retry can never fix.
nonisolated enum GameServerRejection {
    /// A check failed (`23514`, such as a word that is no longer on offer or a
    /// round that already ended), or a role rule broke (`42501` with a message
    /// about whose turn it is or who may act). Access errors keep retrying,
    /// because access can come back.
    static func isPermanent(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        switch code {
        case "23514":
            return true
        case "42501":
            return ["not your turn", "only the"].contains { message.contains($0) }
        default:
            return false
        }
    }

    /// `23505`: the server already has this exact write.
    static func isAlreadyDone(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return code == "23505"
    }
}

// MARK: - Pick a word

/// Starts a round on the server. The drawing and the guesses that follow wait
/// for it, and it waits for this person's earlier guesses, because the turn
/// becomes theirs only once a correct guess or a give up has landed.
///
/// When the server refuses the word, the round never exists. A drawing already
/// made for it is not sent. It is kept for the drawer's next round instead.
struct PickDrawWordPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .pickDrawWord

    private let gateway: any GamesGateway
    private let cache: any GamesCaching
    private let drawingStore: any GameDrawingStoring

    init(gateway: any GamesGateway, cache: any GamesCaching, drawingStore: any GameDrawingStoring) {
        self.gateway = gateway
        self.cache = cache
        self.drawingStore = drawingStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GamePickWordPayload.self, from: data)
        else {
            return .terminalFailure("Missing word pick payload")
        }

        if try await hasEarlierTurnEnder(before: operation, context: context) {
            return .retry(after: nil)
        }

        do {
            _ = try await gateway.pickWord(payload, operation: operation.operation)
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isAlreadyDone(error) {
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isPermanent(error) {
            let keptDrawing = try await keepDrawing(of: payload.roundID, owner: operation.ownerUserID, context: context)
            await cache.recordNotice(
                keptDrawing ? .wordRejectedDrawingKept : .wordRejected,
                ownerUserID: operation.ownerUserID
            )
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }

    /// Moves the drawing made for the refused round, queued or still a draft, to
    /// the rescued slot, and stops the queued send. Returns whether there was one.
    private func keepDrawing(of roundID: UUID, owner: UUID, context: SyncContext) async throws -> Bool {
        let decoder = JSONDecoder()
        let queued = try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: owner, kind: .submitGameDrawing)
            .compactMap { snapshot -> (id: UUID, drawing: Data)? in
                guard let data = snapshot.requestData,
                      let payload = try? decoder.decode(GameSubmitDrawingPayload.self, from: data),
                      payload.roundID == roundID
                else { return nil }
                return (snapshot.operation.id, payload.drawingData)
            }
        guard let drawing = queued.last?.drawing ?? drawingStore.draft(ownerUserID: owner, roundID: roundID) else {
            return false
        }
        // Saved before the queued send stops, so a crash in between loses nothing.
        drawingStore.saveRescuedDrawing(drawing, ownerUserID: owner)
        drawingStore.removeDraft(ownerUserID: owner, roundID: roundID)
        for operation in queued {
            try await context.pendingOperationStore.markTerminalFailure(
                clientOperationID: operation.id,
                errorDescription: "The word pick for this drawing was refused",
                at: Date()
            )
        }
        return true
    }

    private func hasEarlierTurnEnder(
        before operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        for kind in [SyncPendingOperationKind.submitGameGuess, .giveUpGameRound] {
            let earlier = try await context.pendingOperationStore
                .inFlightOperations(ownerUserID: operation.ownerUserID, kind: kind)
                .contains { $0.operation.localCreatedAt <= operation.operation.localCreatedAt }
            if earlier {
                return true
            }
        }
        return false
    }
}

// MARK: - Send the drawing

/// Uploads the finished drawing and submits it, after the word pick for the
/// same round has reached the server.
struct SubmitGameDrawingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitGameDrawing

    private let gateway: any GamesGateway
    private let transfer: any GameDrawingTransferring
    private let cache: any GamesCaching
    private let drawingStore: any GameDrawingStoring

    init(
        gateway: any GamesGateway,
        transfer: any GameDrawingTransferring,
        cache: any GamesCaching,
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
              let payload = try? JSONDecoder().decode(GameSubmitDrawingPayload.self, from: data)
        else {
            return .terminalFailure("Missing drawing payload")
        }

        if try await isWaitingForPick(of: payload.roundID, owner: operation.ownerUserID, context: context) {
            return .retry(after: nil)
        }

        do {
            let assetID = try await transfer.uploadDrawing(
                payload.drawingData,
                gameID: payload.gameID,
                roundID: payload.roundID,
                coupleID: payload.coupleID,
                reserveOperation: payload.reserveOperation,
                finalizeOperation: payload.finalizeOperation
            )
            _ = try await gateway.submitDrawing(
                roundID: payload.roundID,
                mediaAssetID: assetID,
                operation: operation.operation
            )
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isAlreadyDone(error) {
            // The server already has a drawing for this round.
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isPermanent(error) {
            // Nothing the person drew is lost: it goes back on the canvas.
            drawingStore.saveDraft(payload.drawingData, ownerUserID: operation.ownerUserID, roundID: payload.roundID)
            await cache.recordNotice(.drawingRejected, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }

    private func isWaitingForPick(of roundID: UUID, owner: UUID, context: SyncContext) async throws -> Bool {
        try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: owner, kind: .pickDrawWord)
            .contains { snapshot in
                snapshot.requestData
                    .flatMap { try? JSONDecoder().decode(GamePickWordPayload.self, from: $0) }?
                    .roundID == roundID
            }
    }
}

// MARK: - Guess and give up

/// Guesses and give ups of one round go in the order they were made. A wrong
/// guess that has not landed yet would otherwise be refused after the correct
/// one ended the round, and the drawer would never see it.
private func hasEarlierMove(
    in roundID: UUID,
    before operation: PendingSyncOperationSnapshot,
    context: SyncContext
) async throws -> Bool {
    struct Move: Decodable {
        let roundID: UUID
    }
    let order = { (snapshot: PendingSyncOperationSnapshot) in
        (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
    }
    for kind in [SyncPendingOperationKind.submitGameGuess, .giveUpGameRound] {
        let earlier = try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: operation.ownerUserID, kind: kind)
            .contains { other in
                other.operation.id != operation.operation.id
                    && order(other) < order(operation)
                    && other.requestData.flatMap({ try? JSONDecoder().decode(Move.self, from: $0) })?.roundID == roundID
            }
        if earlier {
            return true
        }
    }
    return false
}

struct SubmitGameGuessPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitGameGuess

    private let gateway: any GamesGateway

    init(gateway: any GamesGateway) {
        self.gateway = gateway
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameGuessPayload.self, from: data)
        else {
            return .terminalFailure("Missing guess payload")
        }
        if try await hasEarlierMove(in: payload.roundID, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.submitGuess(
                roundID: payload.roundID,
                guess: payload.guess,
                speedBonus: payload.speedBonus,
                solveMs: payload.solveMs,
                operation: operation.operation
            )
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isAlreadyDone(error) {
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isPermanent(error) {
            // The round ended before this guess arrived. The reveal shows how it ended.
            return .terminalFailure(error.description)
        }
    }
}

struct GiveUpGameRoundPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .giveUpGameRound

    private let gateway: any GamesGateway

    init(gateway: any GamesGateway) {
        self.gateway = gateway
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameGiveUpPayload.self, from: data)
        else {
            return .terminalFailure("Missing give up payload")
        }
        if try await hasEarlierMove(in: payload.roundID, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.giveUp(roundID: payload.roundID, operation: operation.operation)
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isAlreadyDone(error) {
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isPermanent(error) {
            return .terminalFailure(error.description)
        }
    }
}

// MARK: - Save to Memories

/// Uploads the rendered drawing as memory media, then asks the server to save
/// the round. When the partner saved first, the server returns their memory and
/// queues this image for deletion.
struct SaveGameRoundPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .saveGameRoundToMemories

    private let gateway: any GamesGateway
    private let mediaUploader: any MemoryMediaUploading
    private let cache: any GamesCaching

    init(gateway: any GamesGateway, mediaUploader: any MemoryMediaUploading, cache: any GamesCaching) {
        self.gateway = gateway
        self.mediaUploader = mediaUploader
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameSaveRoundPayload.self, from: data)
        else {
            return .terminalFailure("Missing save payload")
        }
        // The server refuses an image without its size.
        guard let size = DrawAndGuessImageRenderer.pixelSize(of: payload.imageData) else {
            await cache.recordNotice(.saveRejected, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure("The image could not be read")
        }
        do {
            let upload = try await mediaUploader.uploadMedia(
                MemoryUploadMedia(
                    data: payload.imageData,
                    purpose: .photo,
                    mimeType: DrawAndGuessImageRenderer.mimeType,
                    fileExtension: DrawAndGuessImageRenderer.fileExtension,
                    width: size.width,
                    height: size.height
                ),
                memoryMediaID: payload.memoryMediaID,
                coupleID: payload.coupleID,
                reserveOperation: payload.reserveOperation,
                finalizeOperation: payload.finalizeOperation
            )
            _ = try await gateway.saveRoundToMemories(
                roundID: payload.roundID,
                memoryID: payload.memoryID,
                mediaAssetID: upload.mediaAssetID,
                memoryDate: payload.memoryDate
            )
            return .succeeded
        } catch let error as PaeoniaConvexError where GameServerRejection.isPermanent(error) {
            await cache.recordNotice(.saveRejected, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}
