import Foundation
import Testing
@testable import PaeoniaApp

struct RelationshipSyncEventsStreamTests {
    @Test func relationshipEventsStreamStoresEventsAndAdvancesCursor() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let firstEvent = try event(
            id: "22222222-2222-2222-2222-222222222222",
            userID: ownerUserID,
            createdAt: 100
        )
        let secondEvent = try event(
            id: "33333333-3333-3333-3333-333333333333",
            userID: ownerUserID,
            createdAt: 200
        )
        let gateway = RelationshipEventsGateway(events: [firstEvent, secondEvent])
        let eventStore = InMemoryRelationshipSyncEventRepository()
        let stream = RelationshipSyncEventsStream(
            gateway: gateway,
            eventStore: eventStore,
            eventApplier: NoOpRelationshipSyncEventApplier()
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let cursor = try await stream.pull(context: context)
        let storedEvents = try await eventStore.events(ownerUserID: ownerUserID)

        #expect(cursor == SyncCursor(updatedAt: secondEvent.createdAt, tieID: secondEvent.id))
        #expect(storedEvents.map(\.id) == [firstEvent.id, secondEvent.id])
    }

    @Test func relationshipEventsStreamDrainsFullPagesAndAppliesBeforeCursorAdvances() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let firstEvent = try event(
            id: "22222222-2222-2222-2222-222222222222",
            userID: ownerUserID,
            createdAt: 100
        )
        let secondEvent = try event(
            id: "33333333-3333-3333-3333-333333333333",
            userID: ownerUserID,
            createdAt: 200
        )
        let gateway = RelationshipEventsGateway(events: [firstEvent, secondEvent])
        let eventStore = InMemoryRelationshipSyncEventRepository()
        let applier = RecordingRelationshipSyncEventApplier()
        let stream = RelationshipSyncEventsStream(
            gateway: gateway,
            eventStore: eventStore,
            eventApplier: applier,
            pageSize: 1
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let cursor = try await stream.pull(context: context)
        let storedEvents = try await eventStore.events(ownerUserID: ownerUserID)

        #expect(cursor == SyncCursor(updatedAt: secondEvent.createdAt, tieID: secondEvent.id))
        #expect(storedEvents.map(\.id) == [firstEvent.id, secondEvent.id])
        #expect(await applier.appliedEventIDs == [firstEvent.id, secondEvent.id])
    }

    private func event(
        id: String,
        userID: UUID,
        createdAt: TimeInterval
    ) throws -> SupabaseRelationshipSyncEvent {
        SupabaseRelationshipSyncEvent(
            id: try #require(UUID(uuidString: id)),
            userID: userID,
            coupleID: try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
            initiatedByUserID: nil,
            eventKind: "relationship_ended",
            reason: "left_relationship",
            occurredAt: Date(timeIntervalSince1970: createdAt),
            relationshipStatus: "ended",
            memberStatus: "ended_notice_pending",
            endedAt: Date(timeIntervalSince1970: createdAt),
            deleteAfter: Date(timeIntervalSince1970: createdAt + 2_592_000),
            localPurgeScope: ["relationship": "hide"],
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

private actor RelationshipEventsGateway: SupabaseAccessGateway {
    private let events: [SupabaseRelationshipSyncEvent]

    init(events: [SupabaseRelationshipSyncEvent]) {
        self.events = events
    }

    func loadMyEntitlement() async throws -> SupabaseUserEntitlement? {
        nil
    }

    func loadMyCoupleEntitlement() async throws -> SupabaseCoupleEntitlement? {
        nil
    }

    func loadCurrentRelationshipState() async throws -> SupabaseRelationshipState? {
        nil
    }

    func loadRelationshipSyncEvents(
        after cursor: SyncCursor,
        limit: Int
    ) async throws -> [SupabaseRelationshipSyncEvent] {
        events
            .filter { event in
                guard let updatedAt = cursor.updatedAt else {
                    return true
                }

                if event.createdAt > updatedAt {
                    return true
                }

                if event.createdAt == updatedAt,
                   let tieID = cursor.tieID {
                    return event.id.uuidString > tieID.uuidString
                }

                return false
            }
            .prefix(limit)
        .map { $0 }
    }
}

private actor RecordingRelationshipSyncEventApplier: RelationshipSyncEventApplying {
    private var appliedIDs: [UUID] = []

    var appliedEventIDs: [UUID] {
        appliedIDs
    }

    func apply(
        _ events: [SupabaseRelationshipSyncEvent],
        context _: SyncContext
    ) async throws {
        appliedIDs.append(contentsOf: events.map(\.id))
    }
}
