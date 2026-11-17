import Foundation
import Testing
@testable import PaeoniaApp

struct RelationshipSyncEventApplierTests {
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
            session: session(ownerUserID: ownerUserID, relationshipCoupleID: coupleID)
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
            session: session(ownerUserID: ownerUserID, relationshipCoupleID: coupleID)
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
            session: session(ownerUserID: ownerUserID, activeCoupleID: newCoupleID)
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
            session: session(ownerUserID: ownerUserID)
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
    ) throws -> RemoteRelationshipSyncEvent {
        let resolvedCoupleID = try coupleID ?? #require(
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")
        )
        return RemoteRelationshipSyncEvent(
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

    private func session(
        ownerUserID: UUID,
        activeCoupleID: UUID? = nil,
        relationshipCoupleID: UUID? = nil
    ) -> SyncSession {
        SyncSession(
            userID: ownerUserID,
            activeCoupleID: activeCoupleID,
            relationshipCoupleID: relationshipCoupleID
        )
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
