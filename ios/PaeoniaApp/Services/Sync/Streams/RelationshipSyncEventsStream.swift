import Foundation

struct RelationshipSyncEventsStream: SyncStream {
    nonisolated let streamKey: SyncStreamKey = .relationshipEvents

    private let gateway: any SupabaseAccessGateway
    private let eventStore: any RelationshipSyncEventPersisting
    private let eventApplier: any RelationshipSyncEventApplying
    private let pageSize: Int

    nonisolated init(
        gateway: any SupabaseAccessGateway,
        eventStore: any RelationshipSyncEventPersisting,
        eventApplier: any RelationshipSyncEventApplying = RelationshipSyncEventApplier(),
        pageSize: Int = 100
    ) {
        self.gateway = gateway
        self.eventStore = eventStore
        self.eventApplier = eventApplier
        self.pageSize = pageSize
    }

    nonisolated func scope(for _: SyncSession) -> SyncStreamScope? {
        SyncStreamScope(kind: .user)
    }

    func pull(context: SyncContext) async throws -> SyncCursor? {
        var cursor = context.streamCursor
        var nextCursor: SyncCursor?

        while true {
            try Task.checkCancellation()

            let events = try await gateway.loadRelationshipSyncEvents(
                after: cursor,
                limit: pageSize
            )
            guard !events.isEmpty else {
                return nextCursor
            }

            try await eventStore.save(events)
            try await eventApplier.apply(events, context: context)

            guard let lastEvent = events.last else {
                return nextCursor
            }

            cursor = SyncCursor(
                updatedAt: lastEvent.createdAt,
                tieID: lastEvent.id
            )
            nextCursor = cursor

            if events.count < pageSize {
                return nextCursor
            }
        }
    }

    func push(context _: SyncContext) async throws {}
}
