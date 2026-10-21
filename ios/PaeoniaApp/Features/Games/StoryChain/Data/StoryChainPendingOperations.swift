import Foundation

// What each queued Story Chain write carries. A start, a line and a name are
// queued as `StoryChainQueuedStart`, `StoryChainQueuedLine` and
// `StoryChainQueuedName` (see `StoryChainPendingWork.swift`). The ids are chosen
// on this phone, so a retry after a lost response replays the same requests.

/// `storyChain:mark_story_seen`. This person moved past a finished story.
nonisolated struct StoryChainSeenPayload: Codable, Equatable, Sendable {
    let storyID: UUID
}

// MARK: - Reading the queue

nonisolated extension StoryChainPendingWork {
    /// Reads the queue. Payloads that fail to decode are skipped. Returns nil
    /// when the queue could not be read: treating that as an empty queue would
    /// make a queued move look lost, so the screen keeps what it shows.
    static func load(
        from store: any PendingSyncOperationPersisting,
        ownerUserID: UUID
    ) async -> StoryChainPendingWork? {
        var work = StoryChainPendingWork()
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
                work.isHeldOnPhone = true
            }
            return operations.compactMap { operation in
                operation.requestData.flatMap { try? decoder.decode(Payload.self, from: $0) }
            }
        }
        do {
            work.starts = try await read(.storyChainStartStory)
            work.lines = try await read(.storyChainAddLine)
            work.names = try await read(.storyChainNameStory)
            let seen: [StoryChainSeenPayload] = try await read(.storyChainMarkSeen, isMove: false)
            work.seenStoryIDs = Set(seen.map(\.storyID))
        } catch {
            return nil
        }
        return work
    }
}

// MARK: - Queueing

/// Saves the moves of Story Chain in the pending operations. The screen shows
/// each move's effect at once and nudges the sync to send it. Each method
/// throws when the phone could not save the move, so the screen can say so.
@MainActor
struct StoryChainMoveQueue {
    private let dependencies: GamesDependencies

    init(dependencies: GamesDependencies) {
        self.dependencies = dependencies
    }

    func start(_ start: StoryChainQueuedStart, ownerUserID: UUID) async throws {
        try await enqueue(
            .storyChainStartStory,
            scope: "story-chain-start:\(Self.key(start.storyID))",
            payload: start,
            ownerUserID: ownerUserID
        )
    }

    func addLine(_ line: StoryChainQueuedLine, ownerUserID: UUID) async throws {
        try await enqueue(
            .storyChainAddLine,
            scope: "story-chain-line:\(Self.key(line.lineID))",
            payload: line,
            ownerUserID: ownerUserID
        )
    }

    func name(_ name: StoryChainQueuedName, ownerUserID: UUID) async throws {
        try await enqueue(
            .storyChainNameStory,
            scope: "story-chain-name:\(Self.key(name.storyID))",
            payload: name,
            ownerUserID: ownerUserID
        )
    }

    func markSeen(storyID: UUID, ownerUserID: UUID) async throws {
        try await enqueue(
            .storyChainMarkSeen,
            scope: "story-chain-seen:\(Self.key(storyID))",
            payload: StoryChainSeenPayload(storyID: storyID),
            ownerUserID: ownerUserID
        )
    }

    private func enqueue(
        _ kind: SyncPendingOperationKind,
        scope: String,
        payload: some Encodable,
        ownerUserID: UUID
    ) async throws {
        try await dependencies.pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: dependencies.operationProvider.makeOperation(),
                operationKind: kind,
                idempotencyScope: scope,
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    private static func key(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
