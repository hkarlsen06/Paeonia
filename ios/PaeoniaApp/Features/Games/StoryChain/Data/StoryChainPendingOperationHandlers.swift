import Foundation

/// The Story Chain handlers for the outbox drain. The Games registry adds them
/// with one line (`GamesPendingOperationRegistry`).
nonisolated enum StoryChainPendingOperations {
    static func handlers(client: PaeoniaConvexClient) -> [any PendingSyncOperationHandling] {
        handlers(
            gateway: LiveGamesGateway(client: client),
            cache: FileStoryChainCache.shared,
            gamesCache: FileGamesCache.shared
        )
    }

    /// `gamesCache` keeps the count of refusals the phone has no rule for, which
    /// every game shares.
    static func handlers(
        gateway: any StoryChainGateway,
        cache: any StoryChainCaching,
        gamesCache: any GamesCaching
    ) -> [any PendingSyncOperationHandling] {
        [
            StoryChainStartPendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache),
            StoryChainLinePendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache),
            StoryChainNamePendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache),
            StoryChainSeenPendingOperationHandler(gateway: gateway, cache: cache),
            StoryChainStarPendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache),
        ]
    }
}

// MARK: - Shared steps

/// The server took a move. Reads the server's state before the move leaves the
/// queue, so the screen keeps showing the move while the live feed catches up
/// instead of falling back to the state from before it. When the read fails,
/// the move stays in the queue and the next try replays it, which the server
/// answers from its record of the operation, and reads again. That try comes
/// after a few seconds (`readAfterMoveRetryPolicy`).
func readStoryChainAfterAcceptedMove(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any StoryChainGateway,
    cache: any StoryChainCaching
) async -> PendingSyncOperationSendResult {
    do {
        _ = try await cache.fetchState(from: gateway, ownerUserID: operation.ownerUserID)
        return .succeeded
    } catch {
        return .retry(after: readAfterMoveRetryPolicy.nextRetryDate(
            attemptNumber: operation.attemptCount + 1,
            now: Date()
        ))
    }
}

/// The part of every Story Chain payload that names its story.
nonisolated private struct StoryChainQueuedWrite: Decodable {
    let storyID: UUID
}

/// Whether this person has another Story Chain write in the queue, of one of
/// `kinds`, that has to reach the server first. With a `storyID`, only writes of
/// that story count. With `onlyEarlier`, only writes made before `operation`.
func hasQueuedStoryChainWrite(
    of kinds: [SyncPendingOperationKind],
    storyID: UUID? = nil,
    besides operation: PendingSyncOperationSnapshot,
    onlyEarlier: Bool = false,
    context: SyncContext
) async throws -> Bool {
    let order = { (snapshot: PendingSyncOperationSnapshot) in
        (snapshot.operation.localCreatedAt, snapshot.operation.clientSequence)
    }
    let decoder = JSONDecoder()
    for kind in kinds {
        let queued = try await context.pendingOperationStore
            .inFlightOperations(ownerUserID: operation.ownerUserID, kind: kind)
        let found = queued.contains { other in
            guard other.operation.id != operation.operation.id else { return false }
            guard !onlyEarlier || order(other) < order(operation) else { return false }
            guard let storyID else { return true }
            let write = other.requestData.flatMap { try? decoder.decode(StoryChainQueuedWrite.self, from: $0) }
            return write?.storyID == storyID
        }
        if found {
            return true
        }
    }
    return false
}

/// Sends one move of the story (a start, a line or a name). `move` calls the
/// server. A move the server took, or already had, reads the state before it
/// leaves the queue. A refusal a retry can't fix drops the move and records a
/// notice, so the person hears that it did not go through. `onDrop` runs first,
/// for writes that can no longer be sent without it.
private func sendStoryChainMove(
    _ operation: PendingSyncOperationSnapshot,
    gateway: any StoryChainGateway,
    cache: any StoryChainCaching,
    gamesCache: any GamesCaching,
    onDrop: () async throws -> Void = {},
    move: () async throws -> Void
) async throws -> PendingSyncOperationSendResult {
    do {
        try await move()
        return await readStoryChainAfterAcceptedMove(operation, gateway: gateway, cache: cache)
    } catch let error as PaeoniaConvexError {
        if GameServerRejection.isAlreadyDone(error) {
            return await readStoryChainAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        }
        guard await GameServerRejection.shouldDrop(error, of: operation, cache: gamesCache) else { throw error }
        try await onDrop()
        await cache.recordNotice(.moveRejected, ownerUserID: operation.ownerUserID)
        LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
        return .terminalFailure(error.description)
    }
}

// MARK: - Start a story

/// Starts a story. The lines that follow wait for it, and it waits for this
/// person's earlier titles, because the turn to start becomes theirs only once
/// the title has landed.
///
/// When the server refuses the start, the story never exists. The lines, title,
/// seen mark and star queued for it stop too, because nothing can send them.
struct StoryChainStartPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .storyChainStartStory

    private let gateway: any StoryChainGateway
    private let cache: any StoryChainCaching
    private let gamesCache: any GamesCaching

    init(gateway: any StoryChainGateway, cache: any StoryChainCaching, gamesCache: any GamesCaching) {
        self.gateway = gateway
        self.cache = cache
        self.gamesCache = gamesCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(StoryChainQueuedStart.self, from: data)
        else {
            return .terminalFailure("Missing story start payload")
        }
        if try await hasQueuedStoryChainWrite(
            of: [.storyChainNameStory],
            besides: operation,
            onlyEarlier: true,
            context: context
        ) {
            return .retry(after: nil)
        }
        return try await sendStoryChainMove(
            operation,
            gateway: gateway,
            cache: cache,
            gamesCache: gamesCache,
            onDrop: { try await stopMoves(of: payload.storyID, owner: operation.ownerUserID, context: context) },
            move: { _ = try await gateway.startStory(payload, operation: operation.operation) }
        )
    }

    private func stopMoves(of storyID: UUID, owner: UUID, context: SyncContext) async throws {
        let decoder = JSONDecoder()
        let kinds: [SyncPendingOperationKind] = [
            .storyChainAddLine, .storyChainNameStory, .storyChainMarkSeen, .storyChainSetStar,
        ]
        for kind in kinds {
            let queued = try await context.pendingOperationStore.inFlightOperations(ownerUserID: owner, kind: kind)
            for snapshot in queued {
                let write = snapshot.requestData.flatMap { try? decoder.decode(StoryChainQueuedWrite.self, from: $0) }
                guard write?.storyID == storyID else { continue }
                // A line of the refused story goes back into the next composer.
                if kind == .storyChainAddLine,
                   let data = snapshot.requestData,
                   let line = try? decoder.decode(StoryChainQueuedLine.self, from: data) {
                    await cache.rescueLines([line.text], ownerUserID: owner)
                }
                try await context.pendingOperationStore.markTerminalFailure(
                    clientOperationID: snapshot.operation.id,
                    errorDescription: "The start of this story was refused",
                    at: Date()
                )
            }
        }
    }
}

// MARK: - Write a line

/// Sends a line. It waits for the start of its story and for the earlier lines
/// of the same story, so the lines land in the order they were written.
struct StoryChainLinePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .storyChainAddLine

    private let gateway: any StoryChainGateway
    private let cache: any StoryChainCaching
    private let gamesCache: any GamesCaching

    init(gateway: any StoryChainGateway, cache: any StoryChainCaching, gamesCache: any GamesCaching) {
        self.gateway = gateway
        self.cache = cache
        self.gamesCache = gamesCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(StoryChainQueuedLine.self, from: data)
        else {
            return .terminalFailure("Missing story line payload")
        }
        if try await hasQueuedStoryChainWrite(
            of: [.storyChainStartStory],
            storyID: payload.storyID,
            besides: operation,
            context: context
        ) {
            return .retry(after: nil)
        }
        if try await hasQueuedStoryChainWrite(
            of: [.storyChainAddLine],
            storyID: payload.storyID,
            besides: operation,
            onlyEarlier: true,
            context: context
        ) {
            return .retry(after: nil)
        }
        return try await sendStoryChainMove(
            operation,
            gateway: gateway,
            cache: cache,
            gamesCache: gamesCache,
            // The refused line goes back into the next composer, so the words are not lost.
            onDrop: { await cache.rescueLines([payload.text], ownerUserID: operation.ownerUserID) },
            move: { _ = try await gateway.addStoryLine(payload, operation: operation.operation) }
        )
    }
}

// MARK: - Name the story

/// Sends the title. The server finishes the story with it and passes the turn to
/// start the next one.
struct StoryChainNamePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .storyChainNameStory

    private let gateway: any StoryChainGateway
    private let cache: any StoryChainCaching
    private let gamesCache: any GamesCaching

    init(gateway: any StoryChainGateway, cache: any StoryChainCaching, gamesCache: any GamesCaching) {
        self.gateway = gateway
        self.cache = cache
        self.gamesCache = gamesCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context _: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(StoryChainQueuedName.self, from: data)
        else {
            return .terminalFailure("Missing story title payload")
        }
        return try await sendStoryChainMove(
            operation,
            gateway: gateway,
            cache: cache,
            gamesCache: gamesCache,
            move: { _ = try await gateway.nameStory(payload, operation: operation.operation) }
        )
    }
}

// MARK: - After the story is finished

/// Tells the server this person moved past a finished story. It waits for the
/// title of the story, because the server marks only a finished story. The server
/// keeps the first time, so a retry is safe. Only a refusal a retry can never fix
/// drops it, without a notice.
struct StoryChainSeenPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .storyChainMarkSeen

    private let gateway: any StoryChainGateway
    private let cache: any StoryChainCaching

    init(gateway: any StoryChainGateway, cache: any StoryChainCaching) {
        self.gateway = gateway
        self.cache = cache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(StoryChainSeenPayload.self, from: data)
        else {
            return .terminalFailure("Missing story seen payload")
        }
        if try await hasQueuedStoryChainWrite(
            of: [.storyChainNameStory],
            storyID: payload.storyID,
            besides: operation,
            context: context
        ) {
            return .retry(after: nil)
        }
        do {
            try await gateway.markStorySeen(storyID: payload.storyID)
            return await readStoryChainAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            guard GameServerRejection.isPermanent(error) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}

/// Sends a star or an unstar for a finished story. The server sets the value it
/// is given, so sending the same write twice changes nothing, and the writes of
/// one story go in the order they were made, which makes the last one win.
///
/// It waits for the title of the story, because the server stars only a finished
/// story. A refusal that a retry can't fix drops the write without a notice: the
/// star then shows the server's value again.
struct StoryChainStarPendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .storyChainSetStar

    private let gateway: any StoryChainGateway
    private let cache: any StoryChainCaching
    private let gamesCache: any GamesCaching

    init(gateway: any StoryChainGateway, cache: any StoryChainCaching, gamesCache: any GamesCaching) {
        self.gateway = gateway
        self.cache = cache
        self.gamesCache = gamesCache
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let data = operation.requestData,
              let payload = try? JSONDecoder().decode(StoryChainStarPayload.self, from: data)
        else {
            return .terminalFailure("Missing story star payload")
        }
        if try await hasQueuedStoryChainWrite(
            of: [.storyChainNameStory],
            storyID: payload.storyID,
            besides: operation,
            context: context
        ) {
            return .retry(after: nil)
        }
        // An earlier star of the same story goes first, so the last write wins.
        if try await hasQueuedStoryChainWrite(
            of: [.storyChainSetStar],
            storyID: payload.storyID,
            besides: operation,
            onlyEarlier: true,
            context: context
        ) {
            return .retry(after: nil)
        }
        do {
            let result = try await gateway.setStoryStar(storyID: payload.storyID, starred: payload.starred)
            // Kept before the write leaves the queue, so the star never flips back
            // to the server's old value in between.
            await cache.saveStars([payload.storyID: result.starred], ownerUserID: operation.ownerUserID)
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            // The star moved the game's version. Reading the state now keeps a
            // live update from before the star from setting it back.
            return await readStoryChainAfterAcceptedMove(operation, gateway: gateway, cache: cache)
        } catch let error as PaeoniaConvexError {
            guard await GameServerRejection.shouldDrop(error, of: operation, cache: gamesCache) else { throw error }
            LocalStoreChanges.post(.games, ownerUserID: operation.ownerUserID)
            return .terminalFailure(error.description)
        }
    }
}
