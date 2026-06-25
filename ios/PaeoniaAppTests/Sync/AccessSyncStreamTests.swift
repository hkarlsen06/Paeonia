import Foundation
import Testing
@testable import PaeoniaApp

struct AccessSyncStreamTests {
    @Test func accessStreamCachesRelationshipAndEntitlementSnapshot() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let gateway = FakeSupabaseAccessGateway(
            userEntitlement: .testUserEntitlement(userID: ownerUserID),
            coupleEntitlement: try .testCoupleEntitlement(),
            relationshipState: try .testRelationshipState()
        )
        let snapshotStore = InMemoryAccessSyncSnapshotRepository()
        let stream = AccessSyncStream(
            gateway: gateway,
            snapshotStore: snapshotStore
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID),
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let cursor = try await stream.pull(context: context)
        try await stream.push(context: context)
        let snapshot = try await snapshotStore.load(ownerUserID: ownerUserID)

        #expect(cursor == nil)
        #expect(snapshot?.userEntitlement?.userID == ownerUserID)
        #expect(snapshot?.coupleEntitlement?.isEntitled == true)
        #expect(snapshot?.relationshipState?.relationshipStatus == .active)
    }
}

private actor FakeSupabaseAccessGateway: SupabaseAccessGateway {
    private let userEntitlement: SupabaseUserEntitlement?
    private let coupleEntitlement: SupabaseCoupleEntitlement?
    private let relationshipState: SupabaseRelationshipState?

    init(
        userEntitlement: SupabaseUserEntitlement?,
        coupleEntitlement: SupabaseCoupleEntitlement?,
        relationshipState: SupabaseRelationshipState?
    ) {
        self.userEntitlement = userEntitlement
        self.coupleEntitlement = coupleEntitlement
        self.relationshipState = relationshipState
    }

    func loadMyEntitlement() async throws -> SupabaseUserEntitlement? {
        userEntitlement
    }

    func loadMyCoupleEntitlement() async throws -> SupabaseCoupleEntitlement? {
        coupleEntitlement
    }

    func loadCurrentRelationshipState() async throws -> SupabaseRelationshipState? {
        relationshipState
    }

    func loadRelationshipSyncEvents(
        after _: SyncCursor,
        limit _: Int
    ) async throws -> [SupabaseRelationshipSyncEvent] {
        []
    }
}

private extension SupabaseUserEntitlement {
    static func testUserEntitlement(userID: UUID) -> SupabaseUserEntitlement {
        SupabaseUserEntitlement(
            userID: userID,
            isEntitled: true,
            source: "storekit",
            status: "active",
            productID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension SupabaseCoupleEntitlement {
    static func testCoupleEntitlement() throws -> SupabaseCoupleEntitlement {
        try SupabaseCoupleEntitlement(
            coupleID: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            isEntitled: true,
            coveringUserID: UUID(uuidString: "44444444-4444-4444-4444-444444444444"),
            source: "storekit",
            status: "active",
            productID: UUID(uuidString: "55555555-5555-5555-5555-555555555555"),
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension SupabaseRelationshipState {
    static func testRelationshipState() throws -> SupabaseRelationshipState {
        try SupabaseRelationshipState(
            coupleID: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            pairID: #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666")),
            relationshipStatus: .active,
            memberStatus: .active,
            partnerUserID: UUID(uuidString: "44444444-4444-4444-4444-444444444444"),
            partnerDisplayName: "Alex",
            partnerProfilePhotoAssetID: nil,
            startedOn: "2026-06-24",
            endedAt: nil,
            deleteAfter: nil,
            endedNoticeSeenAt: nil
        )
    }
}
