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

    /// How many times the server may refuse a write for a reason this phone does
    /// not know before the write is dropped. Such a refusal can be a server
    /// that has not learned the request yet, so a few tries come first.
    static let unexplainedRefusalLimit = 3

    /// The server answered, and the answer is not one a retry can change.
    /// Offline and sign-in problems are not in this group: they come back as
    /// other errors or as `42501` and `55P03`, which keep retrying. `53300`
    /// keeps retrying too. The server sends it when this person sent too much at
    /// once, such as a phone that comes back online with many drawings to upload.
    static func isUnexplained(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return !["42501", "55P03", "53300"].contains(code) && !isPermanent(error) && !isAlreadyDone(error)
    }

    /// Whether to drop the write now: a permanent refusal, or the
    /// `unexplainedRefusalLimit`th unexplained one. Only unexplained refusals
    /// count, kept in `cache`, so offline tries and waits behind an earlier move
    /// never use up the tries.
    static func shouldDrop(
        _ error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any GamesCaching
    ) async -> Bool {
        await shouldDrop(error, of: operation) { operationID, ownerUserID in
            await cache.recordUnexplainedRefusal(operationID: operationID, ownerUserID: ownerUserID)
        }
    }

    /// The same for a game with its own cache. `recordRefusal` counts one more
    /// unexplained refusal of the write and returns how many there are now.
    static func shouldDrop(
        _ error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        recordRefusal: (_ operationID: UUID, _ ownerUserID: UUID) async -> Int
    ) async -> Bool {
        if isPermanent(error) { return true }
        guard isUnexplained(error) else { return false }
        let refusals = await recordRefusal(operation.operation.id, operation.ownerUserID)
        return refusals >= unexplainedRefusalLimit
    }

    /// `23505`: the server already has this exact write.
    static func isAlreadyDone(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return code == "23505"
    }

    /// The upload reserved for a drawing, a strip or a memory photo is gone, so
    /// replaying its reservation can never work. The server deletes an upload
    /// nothing used within a week, which happens when the phone stays offline that
    /// long after uploading.
    static func isUploadGone(_ error: PaeoniaConvexError) -> Bool {
        guard case let .server(code, message) = error else { return false }
        return (code == "42501" && message.contains("media upload reservation is not available"))
            || (code == "23514" && message.contains("game drawing asset is not usable"))
            || (code == "23514" && message.contains("exquisite corpse drawing asset is not usable"))
            || (code == "23514" && message.contains("exquisite corpse strip asset is not usable"))
            || (code == "23514" && message.contains("memory media asset is not usable"))
    }

    /// A fresh upload is a week from being deleted, so an upload renewed this
    /// recently that is gone again points at another problem. It is not renewed
    /// again, which keeps a loop of new uploads from starting.
    static let renewalCooldown: TimeInterval = 24 * 60 * 60

    static func mayRenewUpload(renewedAt: Date?) -> Bool {
        guard let renewedAt else { return true }
        return Date().timeIntervalSince(renewedAt) > renewalCooldown
    }
}

/// The server took a move. Reads the server's state before the move leaves the
/// queue, so the screen keeps showing the move while the live feed catches up
/// instead of falling back to the state from before it. When the read fails,
/// the move stays in the queue: leaving it would put the old state back on
/// screen, such as the word choice again after a pick, and invite the same move
/// twice. The next try replays the move, which the server answers from its
/// record of the operation, and reads again.
///
/// That next try comes after a few seconds instead of the usual minute, so the
/// screen stops saying "Saved on this phone" soon after the network is fine.
/// The wait grows with each try. A phone that went offline fails on the replay
/// itself, which then waits the usual time, so this never loops fast offline.
func readStateAfterAcceptedMove(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any DrawAndGuessGateway,
    cache: any GamesCaching
) async -> PendingSyncOperationSendResult {
    await readStateAfterAcceptedMove(operation) {
        _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
    }
}

/// The same for a game with its own state. `fetch` reads that state and saves it.
func readStateAfterAcceptedMove(
    _ operation: PendingSyncOperationSnapshot,
    fetch: () async throws -> Void
) async -> PendingSyncOperationSendResult {
    do {
        try await fetch()
        return .succeeded
    } catch {
        return .retry(after: readAfterMoveRetryPolicy.nextRetryDate(
            attemptNumber: operation.attemptCount + 1,
            now: Date()
        ))
    }
}

/// 2, 4, 8, then 15 seconds between reads after a move the server took.
nonisolated let readAfterMoveRetryPolicy = PendingSyncOperationRetryPolicy(baseDelaySeconds: 2, maximumDelaySeconds: 15)

// MARK: - Pick a word

/// Starts a round on the server. The drawing and the guesses that follow wait
/// for it, and it waits for this person's earlier guesses, because the turn
/// becomes theirs only once a correct guess or a give up has landed.
///
/// When the server refuses the word, the round never exists. A drawing already
/// made for it is not sent. It is kept for the drawer's next round instead.
struct PickDrawWordPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .pickDrawWord

    private let gateway: any DrawAndGuessGateway
    private let cache: any GamesCaching
    private let drawingStore: any GameDrawingStoring

    init(gateway: any DrawAndGuessGateway, cache: any GamesCaching, drawingStore: any GameDrawingStoring) {
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
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
            }
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
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
                parent: .drawAndGuessRound(gameID: payload.gameID, roundID: payload.roundID),
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
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                // The server already has a drawing for this round.
                return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
            }
            if GameServerRejection.isUploadGone(error),
               GameServerRejection.mayRenewUpload(renewedAt: payload.renewedAt) {
                return try await sendWithNewUpload(payload, replacing: operation, context: context)
            }
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            // Nothing the person drew is lost: it goes back on the canvas.
            drawingStore.saveDraft(payload.drawingData, ownerUserID: operation.ownerUserID, roundID: payload.roundID)
            await cache.recordNotice(.drawingRejected, ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }

    /// Queues the same drawing with new upload operations, so the kept bytes
    /// upload again, and retires this write. The new one is saved first, so the
    /// drawing is never only in a write that stopped.
    private func sendWithNewUpload(
        _ payload: GameSubmitDrawingPayload,
        replacing operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        func renewed(_ old: SyncClientOperation) -> SyncClientOperation {
            SyncClientOperation(clientID: old.clientID, clientSequence: old.clientSequence)
        }
        var renewedPayload = GameSubmitDrawingPayload(
            gameID: payload.gameID,
            roundID: payload.roundID,
            coupleID: payload.coupleID,
            drawingData: payload.drawingData,
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
                requestData: try JSONEncoder().encode(renewedPayload)
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

// MARK: - Guess and give up

/// Guesses and give ups of one round go in the order they were made. A wrong
/// guess that has not landed yet would otherwise be refused after the correct
/// one ended the round, and the drawer would never see it.
func hasEarlierGameMove(
    in roundID: UUID,
    before operation: PendingSyncOperationSnapshot,
    context: SyncContext,
    kinds: [SyncPendingOperationKind] = [.submitGameGuess, .giveUpGameRound]
) async throws -> Bool {
    struct Move: Decodable {
        let roundID: UUID
    }
    let order = { (snapshot: PendingSyncOperationSnapshot) in
        (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
    }
    for kind in kinds {
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

/// A refusal because the round already ended needs no notice, because the
/// reveal shows how it ended. Any other refusal drops the move, so the person
/// hears about it and can guess or give up again.
private func tellAboutRefusal(
    _ error: PaeoniaConvexError,
    of operation: PendingSyncOperationSnapshot,
    in cache: any GamesCaching
) async {
    guard !GameServerRejection.isPermanent(error) else { return }
    await cache.recordNotice(.moveRejected, ownerUserID: operation.ownerUserID)
    LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
}

struct SubmitGameGuessPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .submitGameGuess

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
              let payload = try? JSONDecoder().decode(GameGuessPayload.self, from: data)
        else {
            return .terminalFailure("Missing guess payload")
        }
        if try await hasEarlierGameMove(in: payload.roundID, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.submitGuess(
                roundID: payload.roundID,
                guess: payload.guess,
                speedBonus: payload.speedBonus,
                solveMs: payload.solveMs,
                hintsUsed: payload.hintsUsed,
                operation: operation.operation
            )
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
            }
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            await tellAboutRefusal(error, of: operation, in: cache)
            return .terminalFailure(error.description)
        }
    }
}

struct GiveUpGameRoundPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .giveUpGameRound

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
              let payload = try? JSONDecoder().decode(GameGiveUpPayload.self, from: data)
        else {
            return .terminalFailure("Missing give up payload")
        }
        if try await hasEarlierGameMove(in: payload.roundID, before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.giveUp(roundID: payload.roundID, operation: operation.operation)
            return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await readStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
            }
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
            await tellAboutRefusal(error, of: operation, in: cache)
            return .terminalFailure(error.description)
        }
    }
}
