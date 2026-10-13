import Foundation
import PencilKit

// MARK: - Save to Memories

/// Uploads the rendered drawing as memory media, then asks the server to save
/// the round. When the partner saved first, the server returns their memory and
/// queues this image for deletion. It waits for this person's guesses and give
/// up of the round, because the server saves only a finished round. A save
/// queued before the drawer's final drawing was on the phone renders that
/// drawing here, once the server has it.
struct SaveGameRoundPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .saveGameRoundToMemories

    private let gateway: any GamesGateway
    private let mediaUploader: any MemoryMediaUploading
    private let cache: any GamesCaching
    private let transfer: any GameDrawingTransferring
    private let drawingStore: any GameDrawingStoring

    init(
        gateway: any GamesGateway,
        mediaUploader: any MemoryMediaUploading,
        cache: any GamesCaching,
        transfer: any GameDrawingTransferring,
        drawingStore: any GameDrawingStoring
    ) {
        self.gateway = gateway
        self.mediaUploader = mediaUploader
        self.cache = cache
        self.transfer = transfer
        self.drawingStore = drawingStore
    }

    private enum SubmittedImage {
        /// The drawer's drawing is not on the server yet.
        case waiting
        /// The server has no such round for the couple, or its drawing can't be read.
        case unavailable
        case rendered(Data)
    }

    private func image(
        for payload: GameSaveRoundPayload,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> SubmittedImage {
        if let ready = payload.imageData {
            return .rendered(ready)
        }
        return try await renderSubmittedDrawing(of: payload.roundID, for: operation, context: context)
    }

    /// Renders the drawer's drawing of the round from the server's copy. The
    /// cache can be empty after a privacy purge or miss an old round, so a round
    /// it doesn't know is read from the server by id. A failed read throws, and
    /// the save tries again later.
    private func renderSubmittedDrawing(
        of roundID: UUID,
        for operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> SubmittedImage {
        let owner = operation.ownerUserID
        // This person's own drawing of the round goes first.
        let ownDrawingQueued = try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: owner, kind: .submitGameDrawing)
            .contains { snapshot in
                snapshot.requestData
                    .flatMap { try? JSONDecoder().decode(GameSubmitDrawingPayload.self, from: $0) }?
                    .roundID == roundID
            }
        if ownDrawingQueued { return .waiting }
        let state = await cache.document(ownerUserID: owner).state
        var round = state.flatMap { state in
            ([state.currentRound].compactMap(\.self) + state.recentRounds).first { $0.id == roundID }
        }
        if round?.drawingMediaAssetID == nil {
            round = try await gateway.loadDrawAndGuessRound(roundID: roundID)
        }
        guard let round else { return .unavailable }
        guard let assetID = round.drawingMediaAssetID else { return .waiting }
        let data: Data
        if let kept = drawingStore.downloadedDrawing(mediaAssetID: assetID) {
            data = kept
        } else {
            data = try await transfer.downloadDrawing(mediaAssetID: assetID)
            drawingStore.saveDownloadedDrawing(data, mediaAssetID: assetID)
        }
        guard let drawing = try? PKDrawing(data: data),
              let image = await DrawAndGuessImageRenderer.render(drawing)
        else { return .unavailable }
        return .rendered(image)
    }

    private func tellSaveRejected(owner: UUID) async {
        await cache.recordNotice(.saveRejected, ownerUserID: owner)
        LocalStoreChanges.post(.games, ownerUserID: owner)
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameSaveRoundPayload.self, from: data)
        else {
            return .terminalFailure("Missing save payload")
        }
        if try await hasEarlierGameMove(in: payload.roundID, before: operation, context: context) {
            return .retry(after: nil)
        }
        let imageData: Data
        switch try await image(for: payload, operation: operation, context: context) {
        case .waiting:
            return .retry(after: nil)
        case .unavailable:
            await tellSaveRejected(owner: operation.ownerUserID)
            return .terminalFailure("The drawing for this round could not be found")
        case let .rendered(rendered):
            imageData = rendered
        }
        // The server refuses an image without its size.
        guard let size = DrawAndGuessImageRenderer.pixelSize(of: imageData) else {
            await tellSaveRejected(owner: operation.ownerUserID)
            return .terminalFailure("The image could not be read")
        }
        do {
            try await uploadAndSave(imageData, width: size.width, height: size.height, payload: payload)
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isUploadGone(error), GameServerRejection.mayRenewUpload(renewedAt: payload.renewedAt) {
                return try await saveWithNewUpload(payload, replacing: operation, context: context)
            }
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            await tellSaveRejected(owner: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }

    /// The photo uploaded for this save was deleted because the save waited a
    /// week, so replaying its reservation keeps failing. Queues the same save
    /// with new upload operations and a new memory media id, and retires this
    /// write. The new one is saved first, so the yes is never only in a write
    /// that stopped.
    private func saveWithNewUpload(
        _ payload: GameSaveRoundPayload,
        replacing operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        func renewed(_ old: SyncClientOperation) -> SyncClientOperation {
            SyncClientOperation(clientID: old.clientID, clientSequence: old.clientSequence)
        }
        var renewedPayload = GameSaveRoundPayload(
            roundID: payload.roundID,
            coupleID: payload.coupleID,
            memoryID: payload.memoryID,
            memoryMediaID: UUID(),
            imageData: payload.imageData,
            memoryDate: payload.memoryDate,
            reserveOperation: renewed(payload.reserveOperation),
            finalizeOperation: renewed(payload.finalizeOperation)
        )
        renewedPayload.renewedAt = Date()
        try await context.pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: operation.ownerUserID,
                // Same place in the order as the write it replaces.
                operation: SyncClientOperation(
                    clientID: operation.operation.clientID,
                    clientSequence: operation.operation.clientSequence,
                    localCreatedAt: operation.operation.localCreatedAt
                ),
                operationKind: .saveGameRoundToMemories,
                idempotencyScope: operation.idempotencyScope,
                requestData: try JSONEncoder().encode(renewedPayload)
            )
        )
        return .terminalFailure("The upload expired. The save was queued again with a new upload.")
    }

    private func uploadAndSave(_ imageData: Data, width: Int, height: Int, payload: GameSaveRoundPayload) async throws {
        let upload = try await mediaUploader.uploadMedia(
            MemoryUploadMedia(
                data: imageData,
                purpose: .photo,
                mimeType: DrawAndGuessImageRenderer.mimeType,
                fileExtension: DrawAndGuessImageRenderer.fileExtension,
                width: width,
                height: height
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
    }
}
