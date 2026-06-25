import Foundation
import SwiftData

protocol RelationshipSyncEventPersisting: Actor {
    func save(_ events: [SupabaseRelationshipSyncEvent]) async throws
    func events(ownerUserID: UUID) async throws -> [SupabaseRelationshipSyncEvent]
    func deleteEvents(ownerUserID: UUID) async throws
}

actor SwiftDataRelationshipSyncEventRepository: RelationshipSyncEventPersisting {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
    }

    func save(_ events: [SupabaseRelationshipSyncEvent]) async throws {
        guard !events.isEmpty else {
            return
        }

        let context = ModelContext(container)

        for event in events {
            let purgeScopeData = try encoder.encode(event.localPurgeScope)

            if let existingEvent = try fetchEvent(id: event.id, in: context) {
                existingEvent.update(from: event, localPurgeScopeData: purgeScopeData)
            } else {
                context.insert(
                    LocalRelationshipSyncEvent(
                        event: event,
                        localPurgeScopeData: purgeScopeData
                    )
                )
            }
        }

        try context.save()
    }

    func events(ownerUserID: UUID) async throws -> [SupabaseRelationshipSyncEvent] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalRelationshipSyncEvent>(
            predicate: #Predicate { event in
                event.ownerUserID == ownerUserID
            },
            sortBy: [
                SortDescriptor(\.createdAt),
                SortDescriptor(\.id)
            ]
        )

        return try context.fetch(descriptor).map(event(from:))
    }

    func deleteEvents(ownerUserID: UUID) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalRelationshipSyncEvent>(
            predicate: #Predicate { event in
                event.ownerUserID == ownerUserID
            }
        )

        for event in try context.fetch(descriptor) {
            context.delete(event)
        }

        try context.save()
    }

    private func fetchEvent(
        id: UUID,
        in context: ModelContext
    ) throws -> LocalRelationshipSyncEvent? {
        var descriptor = FetchDescriptor<LocalRelationshipSyncEvent>(
            predicate: #Predicate { event in
                event.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func event(
        from localEvent: LocalRelationshipSyncEvent
    ) throws -> SupabaseRelationshipSyncEvent {
        SupabaseRelationshipSyncEvent(
            id: localEvent.id,
            userID: localEvent.ownerUserID,
            coupleID: localEvent.coupleID,
            initiatedByUserID: localEvent.initiatedByUserID,
            eventKind: localEvent.eventKind,
            reason: localEvent.reason,
            occurredAt: localEvent.occurredAt,
            relationshipStatus: localEvent.relationshipStatus,
            memberStatus: localEvent.memberStatus,
            endedAt: localEvent.endedAt,
            deleteAfter: localEvent.deleteAfter,
            localPurgeScope: try decoder.decode(
                [String: String].self,
                from: localEvent.localPurgeScopeData ?? Data("{}".utf8)
            ),
            createdAt: localEvent.createdAt,
            updatedAt: localEvent.updatedAt
        )
    }
}

actor InMemoryRelationshipSyncEventRepository: RelationshipSyncEventPersisting {
    private var eventsByID: [UUID: SupabaseRelationshipSyncEvent] = [:]

    func save(_ events: [SupabaseRelationshipSyncEvent]) async throws {
        for event in events {
            eventsByID[event.id] = event
        }
    }

    func events(ownerUserID: UUID) async throws -> [SupabaseRelationshipSyncEvent] {
        eventsByID.values
            .filter { $0.userID == ownerUserID }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }

                return $0.createdAt < $1.createdAt
            }
    }

    func deleteEvents(ownerUserID: UUID) async throws {
        eventsByID = eventsByID.filter { $0.value.userID != ownerUserID }
    }
}
