import Foundation

// What each queued Consensio write carries, how the queue is read, and how each
// write is sent. A payload fixes its ids up front, so a retry after a lost
// response replays the same request.

/// `consensio:place_consensio_spot`. The client makes the round id.
nonisolated struct ConsensioPlacePayload: Codable, Equatable, Sendable {
    let roundID: UUID
    /// The round this placement makes. The server refuses it once that turn moved on.
    let roundNumber: Int
    let topic: ConsensioTopicChoice
    let spot: Int
    let createdAt: Date
}

/// `consensio:guess_consensio_spot`.
nonisolated struct ConsensioGuessPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let guess: Int
    let createdAt: Date
}

/// This person moved past the reveal of a round.
nonisolated struct ConsensioRevealSeenPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// This phone's unsent moves, and what this person has already seen.
nonisolated struct ConsensioPendingWork: Equatable, Sendable {
    /// Placements made on this phone and not yet on the server, oldest first.
    var placements: [ConsensioPlacePayload] = []
    /// Round id to the guess made on this phone and not yet on the server.
    var guesses: [UUID: Int] = [:]
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

nonisolated extension ConsensioPendingWork {
    /// Reads the queue. Payloads that fail to decode are skipped. A failed read
    /// gives nil, so the screen keeps what it has: treating it as an empty queue
    /// would make a queued move look lost.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> ConsensioPendingWork? {
        var work = ConsensioPendingWork()
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
            work.placements = try await read(.placeConsensioSpot)
            let guesses: [ConsensioGuessPayload] = try await read(.guessConsensioSpot)
            for guess in guesses {
                work.guesses[guess.roundID] = guess.guess
            }
            let seen: [ConsensioRevealSeenPayload] = try await read(.markConsensioRevealSeen, isMove: false)
            work.seenReveals = Set(seen.map(\.roundID))
        } catch {
            return nil
        }
        return work
    }
}

// MARK: - Shared rules

private enum ConsensioQueue {
    /// The two kinds that change whose turn it is. Each waits for the ones made before it.
    static let moveKinds: [SyncPendingOperationKind] = [.placeConsensioSpot, .guessConsensioSpot]

    /// A place or guess of this person that was made before `operation`, so the
    /// moves reach the server in the order they were played.
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
            .inFlightOperations(ownerUserID: ownerUserID, kind: .guessConsensioSpot)
            .contains { snapshot in
                snapshot.requestData
                    .flatMap { try? JSONDecoder().decode(ConsensioGuessPayload.self, from: $0) }?
                    .roundID == roundID
            }
    }

    static func shouldDrop(
        _ error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any ConsensioCaching
    ) async -> Bool {
        await GameServerRejection.shouldDrop(error, of: operation) { operationID, ownerUserID in
            await cache.recordUnexplainedRefusal(operationID: operationID, ownerUserID: ownerUserID)
        }
    }

    /// Reads the server's state before the move leaves the queue, so the screen
    /// keeps showing the move while the live feed catches up.
    static func readState(
        after operation: PendingSyncOperationSnapshot,
        gateway: any ConsensioGateway,
        cache: any ConsensioCaching
    ) async -> PendingSyncOperationSendResult {
        await readStateAfterAcceptedMove(operation) {
            _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
        }
    }

    /// Drops a refused move and tells the screen, which shows the notice once.
    static func drop(
        _ refused: ConsensioRefusedMove,
        error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any ConsensioCaching
    ) async -> PendingSyncOperationSendResult {
        await cache.recordRefusedMove(refused, ownerUserID: operation.ownerUserID)
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure(error.description)
    }
}

// MARK: - Place

/// Places this person's marker on a new round. A refusal a retry can never fix
/// drops it, and the screen puts the topic and marker back with a notice.
struct ConsensioPlacePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .placeConsensioSpot

    private let gateway: any ConsensioGateway
    private let cache: any ConsensioCaching

    init(gateway: any ConsensioGateway, cache: any ConsensioCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(ConsensioPlacePayload.self, from: data)
        else {
            return .terminalFailure("Missing place payload")
        }
        if try await ConsensioQueue.hasEarlierMove(before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.placeConsensioSpot(
                roundID: payload.roundID,
                roundNumber: payload.roundNumber,
                topic: payload.topic,
                spot: payload.spot,
                operation: operation.operation
            )
            return await ConsensioQueue.readState(after: operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await ConsensioQueue.readState(after: operation, gateway: gateway, cache: cache)
            }
            guard await ConsensioQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
            let refused = ConsensioRefusedMove(roundID: payload.roundID, topic: payload.topic, spot: payload.spot)
            return await ConsensioQueue.drop(refused, error: error, of: operation, cache: cache)
        }
    }
}

// MARK: - Guess

/// Sends this person's guess. A round that already has a guess, such as one
/// made on a second phone, reads the server's state, and the screen plays the
/// reveal of that guess. Any other refusal a retry can't fix drops the guess with
/// a notice, and the screen asks for the guess again.
struct ConsensioGuessPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .guessConsensioSpot

    private let gateway: any ConsensioGateway
    private let cache: any ConsensioCaching

    init(gateway: any ConsensioGateway, cache: any ConsensioCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(ConsensioGuessPayload.self, from: data)
        else {
            return .terminalFailure("Missing guess payload")
        }
        if try await ConsensioQueue.hasEarlierMove(before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.guessConsensioSpot(
                roundID: payload.roundID,
                guess: payload.guess,
                operation: operation.operation
            )
            return await ConsensioQueue.readState(after: operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                return await ConsensioQueue.readState(after: operation, gateway: gateway, cache: cache)
            }
            if case let .server(code: "23514", message: message) = error, message.contains("already has a guess") {
                // The other guess is the one that counts. The guess leaves the queue only
                // once the server's state with it is here, so the reveal never falls back.
                return await ConsensioQueue.readState(after: operation, gateway: gateway, cache: cache)
            }
            guard await ConsensioQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
            return await ConsensioQueue.drop(
                ConsensioRefusedMove(roundID: payload.roundID),
                error: error,
                of: operation,
                cache: cache
            )
        }
    }
}

// MARK: - Seen

/// Tells the server this person moved past a reveal. It waits for this person's
/// guess of the round, because the server refuses the mark until the guess is there.
/// A refusal a retry can never fix drops the mark without a notice.
struct ConsensioRevealSeenOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .markConsensioRevealSeen

    private let gateway: any ConsensioGateway
    private let cache: any ConsensioCaching

    init(gateway: any ConsensioGateway, cache: any ConsensioCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(ConsensioRevealSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing reveal seen payload")
        }
        if try await ConsensioQueue.hasGuessInFlight(
            for: payload.roundID,
            ownerUserID: operation.ownerUserID,
            context: context
        ) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.markConsensioRevealSeen(roundID: payload.roundID)
            return await ConsensioQueue.readState(after: operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            guard await ConsensioQueue.shouldDrop(error, of: operation, cache: cache) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}
