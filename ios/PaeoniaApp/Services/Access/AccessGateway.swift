import Foundation

protocol AccessGateway: Actor {
    func loadAccessSnapshot() async throws -> RemoteAccessSnapshot
    func loadRelationshipSyncEvents(
        after cursor: SyncCursor,
        limit: Int
    ) async throws -> [RemoteRelationshipSyncEvent]
    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws
}

actor LiveAccessGateway: AccessGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadAccessSnapshot() async throws -> RemoteAccessSnapshot {
        let rows: FirstRow<RemoteAccessSnapshot> = try await client.mutation("access:get_access_snapshot")

        return rows.row ?? RemoteAccessSnapshot(
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: nil
        )
    }

    func loadRelationshipSyncEvents(
        after cursor: SyncCursor,
        limit: Int
    ) async throws -> [RemoteRelationshipSyncEvent] {
        try await client.mutation(
            "relationship:get_relationship_sync_events",
            args: RelationshipSyncEventsRequest(
                afterCreatedAt: cursor.updatedAt,
                afterID: cursor.tieID,
                limit: limit
            )
        )
    }

    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws {
        // The backend keys the update on the signed-in user, so an anonymous
        // request would silently mark nothing.
        try await PaeoniaSignedIn.require(isSignedIn)

        try await client.mutation(
            "relationship:mark_relationship_ended_notice_seen",
            args: MarkRelationshipEndedNoticeSeenRequest(coupleID: coupleID)
        )
    }
}

nonisolated private struct RelationshipSyncEventsRequest: Encodable {
    let afterCreatedAt: Date?
    let afterID: UUID?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case afterCreatedAt = "p_after_created_at"
        case afterID = "p_after_id"
        case limit = "p_limit"
    }
}

nonisolated private struct MarkRelationshipEndedNoticeSeenRequest: Encodable {
    let coupleID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
    }
}
