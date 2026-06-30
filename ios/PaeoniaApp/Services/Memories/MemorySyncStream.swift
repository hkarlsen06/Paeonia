import Foundation

struct MemorySyncStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .memories

    private let gateway: any SupabaseMemoryGateway
    private let memoryStore: any MemoryRecordPersisting
    private let pageSize: Int

    nonisolated init(
        gateway: any SupabaseMemoryGateway,
        memoryStore: any MemoryRecordPersisting,
        pageSize: Int = 100
    ) {
        self.gateway = gateway
        self.memoryStore = memoryStore
        self.pageSize = pageSize
    }

    nonisolated func scope(for session: SyncSession) -> SyncStreamScope? {
        guard let coupleID = session.activeCoupleID else {
            return nil
        }

        return SyncStreamScope(kind: .couple, id: coupleID)
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        var cursor = context.streamCursor
        var didAdvance = false

        while true {
            let rows = try await gateway.loadMemories(
                updatedAfter: cursor.updatedAt,
                cursorMemoryID: cursor.tieID,
                limit: pageSize
            )

            guard !rows.isEmpty else {
                return didAdvance ? cursor : context.streamCursor
            }

            try await memoryStore.saveRemote(
                rows,
                ownerUserID: context.session.userID,
                mergePolicy: .preserveLocalChanges
            )

            guard let last = rows.last else {
                return cursor
            }

            cursor = SyncCursor(updatedAt: last.syncUpdatedAt, tieID: last.memoryID)
            didAdvance = true

            if rows.count < pageSize {
                return cursor
            }

            try Task.checkCancellation()
        }
    }

    func push(context _: SyncContext) async throws {}
}
