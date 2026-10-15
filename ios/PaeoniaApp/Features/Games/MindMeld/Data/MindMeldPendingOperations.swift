import Foundation

// What each queued Mind Meld write carries, how the queue is read, and how each
// write is sent. A payload fixes its ids up front, so a retry after a lost
// response replays the same request.

/// `mindMeld:lock_mind_meld_word`. The word is the one the person locked in,
/// trimmed and with single spaces.
nonisolated struct MindMeldLockPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let gameID: UUID
    let word: String
    let createdAt: Date
}

/// `mindMeld:count_mind_meld_round`: counts a near miss as a match.
nonisolated struct MindMeldCountPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// This person moved past the reveal of a round.
nonisolated struct MindMeldRevealSeenPayload: Codable, Equatable, Sendable {
    let roundID: UUID
    let createdAt: Date
}

/// This person saw how a finished game ended.
nonisolated struct MindMeldEndSeenPayload: Codable, Equatable, Sendable {
    let gameID: UUID
    let createdAt: Date
}

nonisolated extension MindMeldPendingWork {
    /// Reads the queue. Payloads that fail to decode are skipped. A failed read
    /// gives nil, so the screen keeps what it has: treating it as an empty queue
    /// would make a queued word look lost.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> MindMeldPendingWork? {
        var work = MindMeldPendingWork()
        let decoder = JSONDecoder()
        /// The payloads of one kind that are still in flight, oldest first.
        func read<Payload: Decodable>(
            _ kind: SyncPendingOperationKind,
            isMove: Bool = true
        ) async throws -> [Payload] {
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
            let locks: [MindMeldLockPayload] = try await read(.lockMindMeldWord)
            for lock in locks {
                work.lockedWords[lock.roundID] = lock.word
            }
            let counts: [MindMeldCountPayload] = try await read(.countMindMeldRound)
            work.countedRounds = Set(counts.map(\.roundID))
            let revealsSeen: [MindMeldRevealSeenPayload] = try await read(.markMindMeldRevealSeen, isMove: false)
            work.seenReveals = Set(revealsSeen.map(\.roundID))
            let endsSeen: [MindMeldEndSeenPayload] = try await read(.markMindMeldEndSeen, isMove: false)
            work.seenEnds = Set(endsSeen.map(\.gameID))
        } catch {
            return nil
        }
        return work
    }
}

// MARK: - Shared rules

/// The server took the write. Reads the server's state before the write leaves
/// the queue, so the screen keeps showing it while the live feed catches up
/// instead of falling back to the state from before it. When the read fails the
/// write stays in the queue, and the next try replays it (the server answers from
/// its record of the operation) and reads again.
func readMindMeldStateAfterAcceptedMove(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any MindMeldGateway,
    cache: any MindMeldCaching
) async -> PendingSyncOperationSendResult {
    await readStateAfterAcceptedMove(operation) {
        _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
    }
}

private enum MindMeldRejection {
    /// Whether to drop the write now: a refusal a retry can never fix, or the
    /// `unexplainedRefusalLimit`th refusal for a reason this phone does not know.
    /// Only unexplained refusals count, so offline tries and waits never use up the tries.
    static func shouldDrop(
        _ error: PaeoniaConvexError,
        of operation: PendingSyncOperationSnapshot,
        cache: any MindMeldCaching
    ) async -> Bool {
        if GameServerRejection.isPermanent(error) { return true }
        guard GameServerRejection.isUnexplained(error) else { return false }
        let refusals = await cache.recordUnexplainedRefusal(
            operationID: operation.operation.id,
            ownerUserID: operation.ownerUserID
        )
        return refusals >= GameServerRejection.unexplainedRefusalLimit
    }

    /// The server answers `42501` for a round it does not have, as it does for a
    /// lost access. A count of a near miss deletes the open round after it, so
    /// a word locked in for that round can never land. The state tells the two apart.
    static func isRoundGone(
        _ roundID: UUID,
        after error: PaeoniaConvexError,
        gateway: any MindMeldGateway,
        ownerUserID: UUID
    ) async -> Bool {
        guard case .server(code: "42501", message: _) = error,
              let state = try? await gateway.loadMindMeld(),
              state.userID == ownerUserID
        else { return false }
        return ![state.current, state.previous].compactMap(\.self).contains { game in
            game.rounds.contains { $0.id == roundID }
        }
    }

    /// A lock-in of this person that is still in the queue and matches `matches`.
    static func hasLockInFlight(
        for ownerUserID: UUID,
        context: SyncContext,
        where matches: (MindMeldLockPayload) -> Bool
    ) async throws -> Bool {
        try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: ownerUserID, kind: .lockMindMeldWord)
            .contains { snapshot in
                snapshot.requestData
                    .flatMap { try? JSONDecoder().decode(MindMeldLockPayload.self, from: $0) }
                    .map(matches) ?? false
            }
    }

    /// A count of this person that is still in the queue.
    static func hasCountInFlight(for ownerUserID: UUID, context: SyncContext) async throws -> Bool {
        let counts = try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: ownerUserID, kind: .countMindMeldRound)
        return !counts.isEmpty
    }

    /// A lock-in of this person that was made before `operation`.
    static func hasEarlierLock(
        before operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        let order = { (snapshot: PendingSyncOperationSnapshot) in
            (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
        }
        return try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: operation.ownerUserID, kind: .lockMindMeldWord)
            .contains { $0.operation.id != operation.operation.id && order($0) < order(operation) }
    }
}

/// Count and seen marks. The server answers a repeat with the first result, so a
/// retry is safe. A refusal a retry can never fix drops the write without a
/// notice, because the state the screen reads already shows what happened.
private func sendMindMeldMark(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any MindMeldGateway,
    cache: any MindMeldCaching,
    send: () async throws -> Void
) async throws -> PendingSyncOperationSendResult {
    do {
        try await send()
        return await readMindMeldStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
    } catch let error as PaeoniaConvexError {
        guard await MindMeldRejection.shouldDrop(error, of: operation, cache: cache) else { throw error }
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure(error.description)
    }
}

// MARK: - Lock in

/// Locks in a word. It waits for this person's earlier lock-ins, so the rounds
/// reach the server in the order they were played.
///
/// A refusal a retry can never fix (the round is finished, the word was already
/// used, or it breaks the word rules) drops the write. The word is kept, so the
/// screen puts it back in the field with a notice. A round the server no longer
/// has drops the write without a notice.
struct LockMindMeldWordPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .lockMindMeldWord

    private let gateway: any MindMeldGateway
    private let cache: any MindMeldCaching

    init(gateway: any MindMeldGateway, cache: any MindMeldCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(MindMeldLockPayload.self, from: data)
        else {
            return .terminalFailure("Missing lock payload")
        }
        if try await MindMeldRejection.hasEarlierLock(before: operation, context: context) {
            return .retry(after: nil)
        }
        do {
            _ = try await gateway.lockMindMeldWord(
                roundID: payload.roundID,
                word: payload.word,
                operation: operation.operation
            )
            return await readMindMeldStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            if GameServerRejection.isAlreadyDone(error) {
                // The server already has this person's word for the round.
                return await readMindMeldStateAfterAcceptedMove(operation, gateway: gateway, cache: cache)
            }
            if await MindMeldRejection.shouldDrop(error, of: operation, cache: cache) {
                await cache.recordRefusedWord(
                    MindMeldRefusedWord(roundID: payload.roundID, word: payload.word),
                    ownerUserID: operation.ownerUserID
                )
                LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
                return .terminalFailure(error.description)
            }
            if await MindMeldRejection.isRoundGone(
                payload.roundID,
                after: error,
                gateway: gateway,
                ownerUserID: operation.ownerUserID
            ) {
                LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
                return .terminalFailure("The round no longer exists")
            }
            throw error
        }
    }
}

// MARK: - Count it

struct CountMindMeldPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .countMindMeldRound

    private let gateway: any MindMeldGateway
    private let cache: any MindMeldCaching

    init(gateway: any MindMeldGateway, cache: any MindMeldCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(MindMeldCountPayload.self, from: data)
        else {
            return .terminalFailure("Missing count payload")
        }
        return try await sendMindMeldMark(operation, gateway: gateway, cache: cache) {
            _ = try await gateway.countMindMeldRound(roundID: payload.roundID)
        }
    }
}

// MARK: - Seen marks

/// Tells the server this person moved past the reveal of a round. It waits for
/// this person's lock-in of the same round, because the server refuses the mark
/// until that word is there.
struct MindMeldRevealSeenOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .markMindMeldRevealSeen

    private let gateway: any MindMeldGateway
    private let cache: any MindMeldCaching

    init(gateway: any MindMeldGateway, cache: any MindMeldCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(MindMeldRevealSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing reveal seen payload")
        }
        let isWaiting = try await MindMeldRejection.hasLockInFlight(for: operation.ownerUserID, context: context) {
            $0.roundID == payload.roundID
        }
        if isWaiting {
            return .retry(after: nil)
        }
        return try await sendMindMeldMark(operation, gateway: gateway, cache: cache) {
            _ = try await gateway.markMindMeldRevealSeen(roundID: payload.roundID)
        }
    }
}

/// Tells the server this person saw how a game ended. It waits for this person's
/// lock-ins in that game, because the last one can be the one that ends it, and for
/// this person's counts, because a count melds the game. The server refuses the
/// mark while the game is still in play.
struct MindMeldEndSeenOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .markMindMeldEndSeen

    private let gateway: any MindMeldGateway
    private let cache: any MindMeldCaching

    init(gateway: any MindMeldGateway, cache: any MindMeldCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(MindMeldEndSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing end seen payload")
        }
        var isWaiting = try await MindMeldRejection.hasLockInFlight(for: operation.ownerUserID, context: context) {
            $0.gameID == payload.gameID
        }
        if !isWaiting {
            isWaiting = try await MindMeldRejection.hasCountInFlight(for: operation.ownerUserID, context: context)
        }
        if isWaiting {
            return .retry(after: nil)
        }
        return try await sendMindMeldMark(operation, gateway: gateway, cache: cache) {
            _ = try await gateway.markMindMeldEndSeen(gameID: payload.gameID)
        }
    }
}
