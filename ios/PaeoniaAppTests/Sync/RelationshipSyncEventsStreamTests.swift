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

    @Test func entitlementLossHidesCachesWithoutPurgingOwnedContent() async throws {
        let ownerUserID = UUID()
        let coupleID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let accessLossEvent = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: coupleID,
            createdAt: 100,
            eventKind: "entitlement_lost",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "preserve"
            ]
        )

        try await applier.apply(
            [accessLossEvent],
            context: context(ownerUserID: ownerUserID, relationshipCoupleID: coupleID)
        )

        #expect(
            await privacyPurger.calls == [
                PrivacyPurgeCall(ownerUserID: ownerUserID, scope: .relationshipAccessHidden)
            ]
        )
    }

    @Test func relationshipEndReviewPurgesContentBecauseMVPHasNoRecoverySurface() async throws {
        let ownerUserID = UUID()
        let coupleID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let relationshipEndEvent = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: coupleID,
            createdAt: 100,
            eventKind: "relationship_ended",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "review"
            ]
        )

        try await applier.apply(
            [relationshipEndEvent],
            context: context(ownerUserID: ownerUserID, relationshipCoupleID: coupleID)
        )

        #expect(
            await privacyPurger.calls == [
                PrivacyPurgeCall(
                    ownerUserID: ownerUserID,
                    scope: .relationshipContentPurged(clearAccessSnapshot: false)
                )
            ]
        )
    }

    @Test func oldRelationshipEventCannotPurgeAUsersNewActiveCouple() async throws {
        let ownerUserID = UUID()
        let oldCoupleID = UUID()
        let newCoupleID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let oldRelationshipEnd = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: oldCoupleID,
            createdAt: 100,
            eventKind: "relationship_ended",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "review"
            ]
        )

        try await applier.apply(
            [oldRelationshipEnd],
            context: context(ownerUserID: ownerUserID, activeCoupleID: newCoupleID)
        )

        #expect(await privacyPurger.calls.isEmpty)
    }

    @Test func oldEventCannotOwnerPurgeWhenCurrentRelationshipIdentityIsUnknown() async throws {
        let ownerUserID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let oldRelationshipEnd = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: UUID(),
            createdAt: 100,
            eventKind: "relationship_ended",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "review"
            ]
        )

        try await applier.apply(
            [oldRelationshipEnd],
            context: context(ownerUserID: ownerUserID)
        )

        #expect(await privacyPurger.calls.isEmpty)
    }

    private func event(
        id: String,
        userID: UUID,
        coupleID: UUID? = nil,
        createdAt: TimeInterval,
        eventKind: String = "relationship_ended",
        localPurgeScope: [String: String] = ["relationship": "hide"]
    ) throws -> SupabaseRelationshipSyncEvent {
        let resolvedCoupleID = try coupleID ?? #require(
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")
        )
        return SupabaseRelationshipSyncEvent(
            id: try #require(UUID(uuidString: id)),
            userID: userID,
            coupleID: resolvedCoupleID,
            initiatedByUserID: nil,
            eventKind: eventKind,
            reason: "left_relationship",
            occurredAt: Date(timeIntervalSince1970: createdAt),
            relationshipStatus: "ended",
            memberStatus: "ended_notice_pending",
            endedAt: Date(timeIntervalSince1970: createdAt),
            deleteAfter: Date(timeIntervalSince1970: createdAt + 2_592_000),
            localPurgeScope: localPurgeScope,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func context(
        ownerUserID: UUID,
        activeCoupleID: UUID? = nil,
        relationshipCoupleID: UUID? = nil
    ) -> SyncContext {
        SyncContext(
            session: SyncSession(
                userID: ownerUserID,
                activeCoupleID: activeCoupleID,
                relationshipCoupleID: relationshipCoupleID
            ),
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
    }
}

private actor RelationshipEventsGateway: SupabaseAccessGateway {
    private let events: [SupabaseRelationshipSyncEvent]

    init(events: [SupabaseRelationshipSyncEvent]) {
        self.events = events
    }

    func loadAccessSnapshot() async throws -> SupabaseAccessSnapshot {
        SupabaseAccessSnapshot(
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: nil
        )
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

    func markRelationshipEndedNoticeSeen(coupleID _: UUID) async throws {}
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

private struct PrivacyPurgeCall: Equatable, Sendable {
    let ownerUserID: UUID
    let scope: LocalPrivacyPurgeScope
}

private actor RecordingLocalPrivacyPurger: LocalPrivacyPurging {
    private(set) var calls: [PrivacyPurgeCall] = []

    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) -> LocalPrivacyPurgeResult {
        calls.append(PrivacyPurgeCall(ownerUserID: ownerUserID, scope: scope))
        return .completed
    }
}
