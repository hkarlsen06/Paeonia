import Foundation

// What each queued Guess my spot write carries, how the queue is read, and how
// each write is sent. A payload fixes its ids up front, so a retry after a lost
// response replays the same requests.

/// `guessMySpot:send_guess_my_spot_photo`, with the photo's upload. The photo's
/// bytes are in `GuessMySpotPhotoStore` under the round id.
nonisolated struct GuessMySpotSendPayload: Codable, Equatable, Sendable {
    var details: GuessMySpotSendDetails
    let coupleID: UUID
    let width: Int
    let height: Int
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
    let createdAt: Date
    /// When the send was queued again because its first upload was gone.
    var renewedAt: Date?

    var roundID: UUID { details.roundID }
}

/// `guessMySpot:submit_guess_my_spot_guess`.
nonisolated struct GuessMySpotGuessPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let guess: GuessMySpotCoordinate
    let createdAt: Date
}

/// `guessMySpot:delete_guess_my_spot_round`: a round this person sent, deleted for both.
nonisolated struct GuessMySpotDeletePayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// This person moved past the reveal of a round.
nonisolated struct GuessMySpotRevealSeenPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// This phone's unsent moves, and what this person has already seen.
nonisolated struct GuessMySpotPendingWork: Equatable, Sendable {
    /// Sends made on this phone and not yet on the server, oldest first.
    var sends: [GuessMySpotSendPayload] = []
    /// Round id to the guess made on this phone and not yet on the server.
    var guesses: [UUID: GuessMySpotCoordinate] = [:]
    /// Rounds whose reveal this person has seen, with a mark not yet on the server.
    var seenReveals: Set<UUID> = []
    /// The last send failed while the phone had a connection.
    var lastSendFailedWhileOnline = false
    /// A waiting move has had a try that did not get through, for any reason.
    /// Until then it is on its first send, and the screen says nothing about it
    /// being on this phone, so a normal send never flashes that line.
    var hasFailedMoveAttempt = false

    static let none = Self()
}

nonisolated extension GuessMySpotPendingWork {
    /// Reads the queue. Payloads that fail to decode are skipped. A failed read
    /// gives nil, so the screen keeps what it has: treating it as an empty queue
    /// would make a queued move look lost.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> GuessMySpotPendingWork? {
        var work = GuessMySpotPendingWork()
        let decoder = JSONDecoder()
        func read<Payload: Decodable>(_ kind: SyncPendingOperationKind, isMove: Bool = true) async throws -> [Payload] {
            let operations = try await store.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
            if isMove, operations.contains(where: \.failedWhileOnline) {
                work.lastSendFailedWhileOnline = true
            }
            if isMove, operations.contains(where: \.hasFailedAttempt) {
                work.hasFailedMoveAttempt = true
            }
            return operations.compactMap { operation in
                operation.requestData.flatMap { try? decoder.decode(Payload.self, from: $0) }
            }
        }
        do {
            work.sends = try await read(.guessMySpotSend)
            let guesses: [GuessMySpotGuessPayload] = try await read(.guessMySpotGuess)
            for guess in guesses {
                work.guesses[guess.roundID] = guess.guess
            }
            let seen: [GuessMySpotRevealSeenPayload] = try await read(.guessMySpotRevealSeen, isMove: false)
            work.seenReveals = Set(seen.map(\.roundID))
        } catch {
            return nil
        }
        return work
    }
}

// MARK: - Shared rules

private enum GuessMySpotQueue {
    /// The two kinds that change whose turn it is. Each waits for the ones made before it.
    static let moveKinds: [SyncPendingOperationKind] = [.guessMySpotSend, .guessMySpotGuess]

    /// A send or guess of this person made before `operation`, so the moves
    /// reach the server in the order they were played.
    static func hasEarlierMove(
        before operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        let order = { (snapshot: PendingSyncOperationSnapshot) in
            (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
        }
        for kind in moveKinds {
            let earlier = try await context.pendingOperationStore
                .inFlightOperations(ownerUserID: operation.ownerUserID, kind: kind)
                .contains { $0.operation.id != operation.operation.id && order($0) < order(operation) }
            if earlier { return true }
        }
        return false
    }

    /// A guess of this person for `roundID` that is still in the queue.
    static func hasGuessInFlight(for roundID: UUID, ownerUserID: UUID, context: SyncContext) async throws -> Bool {
        try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: ownerUserID, kind: .guessMySpotGuess)
            .contains { snapshot in
                snapshot.requestData
                    .flatMap { try? JSONDecoder().decode(GuessMySpotGuessPayload.self, from: $0) }?
                    .roundID == roundID
            }
    }

    static func shouldDrop(
        _ error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any GuessMySpotCaching
    ) async -> Bool {
        await GameServerRejection.shouldDrop(error, of: operation) { operationID, ownerUserID in
            await cache.recordUnexplainedRefusal(operationID: operationID, ownerUserID: ownerUserID)
        }
    }

    /// The photo's upload is gone, so replaying its reservation can never work.
    nonisolated static func isPhotoGone(_ error: PaeoniaConvexError) -> Bool {
        if GameServerRejection.isUploadGone(error) { return true }
        guard case let .server(code, message) = error else { return false }
        return (code == "23514" && message.contains("guess my spot photo is not usable"))
            || (code == PaeoniaConvexError.accessDeniedCode && message.contains("guess my spot photo is not available"))
    }

    /// Reads the server's state before the move leaves the queue, so the screen
    /// keeps showing the move while the live feed catches up.
    static func readState(
        after operation: PendingSyncOperationSnapshot,
        gateway: any GuessMySpotGateway,
        cache: any GuessMySpotCaching
    ) async -> PendingSyncOperationSendResult {
        await readStateAfterAcceptedMove(operation) {
            _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
        }
    }

    /// Drops a refused move and tells the screen, which shows the notice once.
    static func drop(
        _ refused: GuessMySpotRefusedMove,
        error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any GuessMySpotCaching
    ) async -> PendingSyncOperationSendResult {
        await cache.recordRefusedMove(refused, ownerUserID: operation.ownerUserID)
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure(error.description)
    }
}

// MARK: - Send

/// Uploads the photo and sends the round. A refusal a retry can never fix drops
/// the send, and the screen puts the photo and the pin back on the check with a
/// notice. The photo file stays until the server has the round or the person
/// sends that photo again.
struct GuessMySpotSendPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .guessMySpotSend

    private let gateway: any GuessMySpotGateway
    private let cache: any GuessMySpotCaching
    private let photos: any GuessMySpotPhotoStoring
    private let namer: any GuessMySpotPlaceNaming
    /// The shared media image cache. The sent photo goes in under its asset id, so
    /// this phone never downloads its own photo.
    private let imageCache: (any MemoryMediaImageCacheWriting)?

    init(
        gateway: any GuessMySpotGateway,
        cache: any GuessMySpotCaching,
        photos: any GuessMySpotPhotoStoring,
        namer: any GuessMySpotPlaceNaming,
        imageCache: (any MemoryMediaImageCacheWriting)?
    ) {
        self.gateway = gateway
        self.cache = cache
        self.photos = photos
        self.namer = namer
        self.imageCache = imageCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              var payload = try? JSONDecoder().decode(GuessMySpotSendPayload.self, from: data)
        else {
            return .terminalFailure("Missing send payload")
        }
        if try await GuessMySpotQueue.hasEarlierMove(before: operation, context: context) {
            return .retry(after: nil)
        }
        guard let jpeg = photos.photo(ownerUserID: operation.ownerUserID, roundID: payload.roundID) else {
            return await dropWithoutPhoto(payload, of: operation)
        }
        if payload.details.placeName == nil {
            // Sent offline: name the place now that there is a connection.
            payload.details.name(await namer.place(for: payload.details.spot))
        }
        do {
            let assetID = try await gateway.uploadGuessMySpotPhoto(
                jpeg,
                width: payload.width,
                height: payload.height,
                roundID: payload.roundID,
                coupleID: payload.coupleID,
                reserve: payload.reserveOperation,
                finalize: payload.finalizeOperation
            )
            await imageCache?.cacheImageData(jpeg, for: assetID)
            _ = try await gateway.sendGuessMySpotPhoto(
                payload.details,
                mediaAssetID: assetID,
                operation: operation.operation
            )
            return await readStateAndForgetPhoto(payload, after: operation)
        } catch let error as PaeoniaConvexError {
            return try await handle(error, payload: payload, operation: operation, context: context)
        }
    }

    /// The server answered the upload or the send with an error.
    private func handle(
        _ error: PaeoniaConvexError,
        payload: GuessMySpotSendPayload,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        if GameServerRejection.isAlreadyDone(error) {
            return await readStateAndForgetPhoto(payload, after: operation)
        }
        if GuessMySpotQueue.isPhotoGone(error), GameServerRejection.mayRenewUpload(renewedAt: payload.renewedAt) {
            return try await sendWithNewUpload(payload, replacing: operation, context: context)
        }
        guard await GuessMySpotQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
        return await GuessMySpotQueue.drop(
            GuessMySpotRefusedMove(roundID: payload.roundID, send: payload),
            error: error,
            of: operation,
            cache: cache
        )
    }

    /// The server has the round. The photo stays on the phone until the state read
    /// after it succeeds too, because a failed read retries the whole send, and the
    /// replay needs the photo to upload again.
    private func readStateAndForgetPhoto(
        _ payload: GuessMySpotSendPayload,
        after operation: PendingSyncOperationSnapshot
    ) async -> PendingSyncOperationSendResult {
        let result = await GuessMySpotQueue.readState(after: operation, gateway: gateway, cache: cache)
        if result == .succeeded {
            photos.remove(ownerUserID: operation.ownerUserID, roundID: payload.roundID)
        }
        return result
    }

    /// The photo file is gone, as after a privacy purge, so nothing can be sent.
    private func dropWithoutPhoto(
        _ payload: GuessMySpotSendPayload,
        of operation: PendingSyncOperationSnapshot
    ) async -> PendingSyncOperationSendResult {
        let refused = GuessMySpotRefusedMove(roundID: payload.roundID)
        await cache.recordRefusedMove(refused, ownerUserID: operation.ownerUserID)
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure("The photo of this send is gone from the phone")
    }

    /// Queues the same send with new upload operations, so the kept photo uploads
    /// again, and retires this write. The new one is saved first, so the photo is
    /// never only in a write that stopped.
    private func sendWithNewUpload(
        _ payload: GuessMySpotSendPayload,
        replacing operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        func renewed(_ old: SyncClientOperation) -> SyncClientOperation {
            SyncClientOperation(clientID: old.clientID, clientSequence: old.clientSequence)
        }
        var renewedPayload = GuessMySpotSendPayload(
            details: payload.details,
            coupleID: payload.coupleID,
            width: payload.width,
            height: payload.height,
            reserveOperation: renewed(payload.reserveOperation),
            finalizeOperation: renewed(payload.finalizeOperation),
            createdAt: payload.createdAt
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
                operationKind: .guessMySpotSend,
                idempotencyScope: operation.idempotencyScope,
                requestData: try JSONEncoder().encode(renewedPayload)
            )
        )
        return .terminalFailure("The upload expired. The photo was queued again with a new upload.")
    }
}

// MARK: - Guess

/// Sends this person's guess. A round that already has a guess, such as one made
/// on a second phone, reads the server's state, and the screen plays the reveal of
/// that guess. Any other refusal a retry can't fix drops the guess with a notice,
/// and the screen asks for the guess again.
struct GuessMySpotGuessPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .guessMySpotGuess

    private let gateway: any GuessMySpotGateway
    private let cache: any GuessMySpotCaching

    init(gateway: any GuessMySpotGateway, cache: any GuessMySpotCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GuessMySpotGuessPayload.self, from: data)
        else {
            return .terminalFailure("Missing guess payload")
        }
        if try await GuessMySpotQueue.hasEarlierMove(before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.submitGuessMySpotGuess(
                roundID: payload.roundID,
                guess: payload.guess,
                operation: operation.operation
            )
            return await GuessMySpotQueue.readState(after: operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await GuessMySpotQueue.readState(after: operation, gateway: gateway, cache: cache)
            }
            if case let .server(code: "23514", message: message) = error, message.contains("already has a guess") {
                // The other guess is the one that counts. The guess leaves the queue only
                // once the server's state with it is here, so the reveal never falls back.
                return await GuessMySpotQueue.readState(after: operation, gateway: gateway, cache: cache)
            }
            guard await GuessMySpotQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
            return await GuessMySpotQueue.drop(
                GuessMySpotRefusedMove(roundID: payload.roundID),
                error: error,
                of: operation,
                cache: cache
            )
        }
    }
}

// MARK: - Seen

/// Tells the server this person moved past a reveal. It waits for this person's
/// guess of the round, because the server refuses the mark until the guess is
/// there. A refusal a retry can never fix drops the mark without a notice.
struct GuessMySpotRevealSeenOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .guessMySpotRevealSeen

    private let gateway: any GuessMySpotGateway
    private let cache: any GuessMySpotCaching

    init(gateway: any GuessMySpotGateway, cache: any GuessMySpotCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GuessMySpotRevealSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing reveal seen payload")
        }
        if try await GuessMySpotQueue.hasGuessInFlight(
            for: payload.roundID,
            ownerUserID: operation.ownerUserID,
            context: context
        ) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.markGuessMySpotRevealSeen(roundID: payload.roundID)
            return await GuessMySpotQueue.readState(after: operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            guard await GuessMySpotQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}

// MARK: - Delete

/// Deletes a round this person sent. "Our guesses" takes it off at once. A refusal a
/// retry can't fix, such as a reveal the partner hasn't seen yet, drops the delete
/// with a notice, and the next read of the map puts the round back.
struct GuessMySpotDeleteRoundOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .guessMySpotDeleteRound

    private let gateway: any GuessMySpotGateway
    private let cache: any GuessMySpotCaching

    init(gateway: any GuessMySpotGateway, cache: any GuessMySpotCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(GuessMySpotDeletePayload.self, from: data)
        else {
            return .terminalFailure("Missing delete payload")
        }
        do {
            _ = try await gateway.deleteGuessMySpotRound(roundID: payload.roundID, operation: operation.operation)
            // The saved map loses the round too, so the next launch doesn't show it until the read.
            let ticket = await cache.historyTicket()
            if let history = try? await gateway.loadGuessMySpotHistory() {
                await cache.saveHistory(history, ownerUserID: operation.ownerUserID, ticket: ticket)
            }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .succeeded
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) { return .succeeded }
            guard await GuessMySpotQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
            return await GuessMySpotQueue.drop(
                GuessMySpotRefusedMove(roundID: payload.roundID),
                error: error,
                of: operation,
                cache: cache
            )
        }
    }
}
