@preconcurrency import ConvexMobile
import Foundation

/// Keeps the couple's memories in the local store up to date.
///
/// `memories:get_memories` returns every row changed after a cursor, oldest first,
/// at most 100 per result. The feed subscribes at the stored cursor. A memory the
/// partner hides or deletes comes back as a changed row, so it disappears here too.
/// When a result has rows, the feed saves them, stores the new cursor, and
/// subscribes again from that cursor. A first launch with a long history pages
/// through it the same way, 100 rows at a time.
nonisolated struct MemoryLiveFeed: LiveFeed {
    let name = "memories"

    /// The Memories tab reads the store, and the Questions tab lists the memory chats. The feed
    /// starts at the stored cursor, so a visit catches up.
    var activation: LiveFeedActivation {
        .whileNeeded([.memoriesTab, .questionsTab])
    }

    private let memoryStore: any MemoryRecordPersisting
    private let stateStore: any SyncStatePersisting
    private let retryDelay: Duration

    init(
        memoryStore: any MemoryRecordPersisting,
        stateStore: any SyncStatePersisting,
        retryDelay: Duration = .seconds(5)
    ) {
        self.memoryStore = memoryStore
        self.stateStore = stateStore
        self.retryDelay = retryDelay
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard let coupleID = session.activeCoupleID else {
            return
        }

        let scope = SyncStreamScope(kind: .couple, id: coupleID)
        var cursor = (try? await stateStore.cursor(
            ownerUserID: session.userID,
            scope: scope,
            streamKey: .memories
        )) ?? SyncCursor()

        while !Task.isCancelled {
            guard let rows = await nextRows(after: cursor, live: live),
                  let last = rows.last
            else {
                return
            }
            let next = SyncCursor(updatedAt: last.syncUpdatedAt, tieID: last.memoryID)
            guard next != cursor else {
                // The server returned rows at or before the cursor. Wait instead of spinning.
                try? await Task.sleep(for: retryDelay)
                continue
            }

            do {
                try await memoryStore.saveRemote(
                    rows,
                    ownerUserID: session.userID,
                    mergePolicy: .preserveLocalChanges
                )
                try await stateStore.markSucceeded(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: .memories,
                    cursor: next,
                    at: Date()
                )
                cursor = next
            } catch {
                // Subscribe again from the old cursor once the store recovers.
                try? await Task.sleep(for: retryDelay)
            }
        }
    }

    /// The first non-empty result after `cursor`, or nil once the task is cancelled.
    /// Dropping the stream cancels the subscription.
    private func nextRows(after cursor: SyncCursor, live: LiveQueryService) async -> [MemoryRemoteRow]? {
        let results = live.subscribe(
            "memories:get_memories",
            args: Self.arguments(for: cursor),
            as: [MemoryRemoteRow].self
        )
        for await result in results {
            if Task.isCancelled {
                return nil
            }
            if case let .value(rows) = result, !rows.isEmpty {
                return rows
            }
        }
        return nil
    }

    private static func arguments(for cursor: SyncCursor) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = [:]
        // The client encoder rounds to the middle of the millisecond. A plain
        // formatter can print `.122` for a stored `.123`, and the server would
        // then return the same row again.
        if let updatedAt = cursor.updatedAt,
           let data = try? PaeoniaConvexClient.encoder.encode(updatedAt),
           let timestamp = try? JSONDecoder().decode(String.self, from: data) {
            args["p_updated_after"] = timestamp
            if let tieID = cursor.tieID {
                args["p_cursor_memory_id"] = tieID.uuidString
            }
        }
        return args
    }
}
