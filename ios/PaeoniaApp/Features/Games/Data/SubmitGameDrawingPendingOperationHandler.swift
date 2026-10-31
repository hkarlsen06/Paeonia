import Foundation

// MARK: - Send the drawing

/// Uploads the finished drawing and submits it, after the word pick for the
/// same round has reached the server.
struct SubmitGameDrawingPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitGameDrawing

    private let gateway: any DrawAndGuessGateway
    private let transfer: any GameDrawingTransferring
    private let cache: any GamesCaching
    private let drawingStore: any GameDrawingStoring

    init(
        gateway: any DrawAndGuessGateway,
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
        let privacyToken = LocalPrivacyWriteGuard.shared.token(ownerUserID: operation.ownerUserID)
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GameSubmitDrawingPayload.self, from: data)
        else {
            return .terminalFailure("Missing drawing payload")
        }
        if let coupleID = context.session.activeCoupleID, coupleID != payload.coupleID {
            return .terminalFailure("The drawing belongs to an earlier relationship")
        }

        if try await isWaitingForPick(of: payload.roundID, owner: operation.ownerUserID, context: context) {
            return .retry(after: nil)
        }

        do {
            let assetID = try await transfer.uploadDrawing(
                payload.drawingData,
                parent: .drawAndGuessRound(gameID: payload.gameID, roundID: payload.roundID,
                                          accessibilityText: payload.drawingAccessibilityText),
                coupleID: payload.coupleID,
                reserveOperation: payload.reserveOperation,
                finalizeOperation: payload.finalizeOperation
            )
            // Kept as the server's copy, so the drawer's own result never has to
            // download it, also after a relaunch while offline.
            drawingStore.saveDownloadedDrawing(payload.drawingData, mediaAssetID: assetID)
            _ = try await gateway.submitDrawing(
                roundID: payload.roundID,
                mediaAssetID: assetID,
                operation: operation.operation
            )
            guard LocalPrivacyWriteGuard.shared.isCurrent(privacyToken) else {
                return .terminalFailure("The drawing belongs to a cleared relationship")
            }
            _ = try? drawingStore.removePublishedDraft(GameDrawingDraftPublication(
                id: payload.draftPublicationID, coupleID: payload.coupleID,
                roundID: payload.roundID, data: payload.drawingData,
                accessibilityText: payload.drawingAccessibilityText
            ), ownerUserID: operation.ownerUserID, privacyToken: privacyToken)
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            return try await handleRefusal(error, payload: payload, operation: operation,
                                          context: context, privacyToken: privacyToken)
        }
    }

    private func handleRefusal(
        _ error: PaeoniaConvexError, payload: GameSubmitDrawingPayload,
        operation: PendingSyncOperationSnapshot, context: SyncContext,
        privacyToken: LocalPrivacyWriteGuard.Token
    ) async throws -> PendingSyncOperationSendResult {
        guard LocalPrivacyWriteGuard.shared.isCurrent(privacyToken) else {
            return .terminalFailure("The drawing belongs to a cleared relationship")
        }
        if GameServerRejection.isAlreadyDone(error) {
            // The server already has a drawing for this round.
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        }
        if GameServerRejection.isUploadGone(error),
           GameServerRejection.mayRenewUpload(renewedAt: payload.renewedAt) {
            return try await sendWithNewUpload(payload, replacing: operation, context: context,
                                               privacyToken: privacyToken)
        }
        guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
        // Nothing the person drew is lost: it goes back on the canvas.
        try drawingStore.saveDraftDescription(
            payload.drawingAccessibilityText ?? "", ownerUserID: operation.ownerUserID,
            coupleID: payload.coupleID, roundID: payload.roundID, privacyToken: privacyToken)
        drawingStore.saveDraft(payload.drawingData, ownerUserID: operation.ownerUserID, roundID: payload.roundID)
        await cache.recordNotice(.drawingRejected, ownerUserID: operation.ownerUserID)
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure(error.description)
    }

    /// Queues the same drawing with new upload operations, so the kept bytes
    /// upload again, and retires this write. The new one is saved first, so the
    /// drawing is never only in a write that stopped.
    private func sendWithNewUpload(
        _ payload: GameSubmitDrawingPayload,
        replacing operation: PendingSyncOperationSnapshot,
        context: SyncContext,
        privacyToken: LocalPrivacyWriteGuard.Token
    ) async throws -> PendingSyncOperationSendResult {
        func renewed(_ old: SyncClientOperation) -> SyncClientOperation {
            SyncClientOperation(clientID: old.clientID, clientSequence: old.clientSequence)
        }
        var renewedPayload = GameSubmitDrawingPayload(
            gameID: payload.gameID,
            roundID: payload.roundID,
            coupleID: payload.coupleID,
            drawingData: payload.drawingData,
            drawingAccessibilityText: payload.drawingAccessibilityText,
            draftPublicationID: payload.draftPublicationID,
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
                operationKind: .submitGameDrawing,
                idempotencyScope: operation.idempotencyScope,
                requestData: try JSONEncoder().encode(renewedPayload),
                privacyToken: privacyToken
            )
        )
        return .terminalFailure("The upload expired. The drawing was queued again with a new upload.")
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
