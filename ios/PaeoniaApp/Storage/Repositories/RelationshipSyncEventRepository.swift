import Foundation
import SwiftData

protocol RelationshipSyncEventPersisting: Actor {
    func save(_ events: [RemoteRelationshipSyncEvent]) async throws
}

actor SwiftDataRelationshipSyncEventRepository: RelationshipSyncEventPersisting {
    private let container: ModelContainer
    private let encoder = JSONEncoder()

    init(container: ModelContainer) {
        self.container = container
    }

    func save(_ events: [RemoteRelationshipSyncEvent]) throws {
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
        postChanges(for: events)
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
}

actor InMemoryRelationshipSyncEventRepository: RelationshipSyncEventPersisting {
    private var eventsByID: [UUID: RemoteRelationshipSyncEvent] = [:]

    func save(_ events: [RemoteRelationshipSyncEvent]) throws {
        for event in events {
            eventsByID[event.id] = event
        }
        postChanges(for: events)
    }

    func events(ownerUserID: UUID) throws -> [RemoteRelationshipSyncEvent] {
        eventsByID.values
            .filter { $0.userID == ownerUserID }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }

                return $0.createdAt < $1.createdAt
            }
    }
}

nonisolated private func postChanges(for events: [RemoteRelationshipSyncEvent]) {
    guard !events.isEmpty else {
        return
    }

    for ownerUserID in Set(events.map(\.userID)) {
        LocalStoreChanges.post(.relationshipEvents, ownerUserID: ownerUserID)
    }
}
