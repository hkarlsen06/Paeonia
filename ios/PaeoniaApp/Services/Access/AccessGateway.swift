import Foundation

protocol AccessGateway: Actor {
    func loadAccessSnapshot() async throws -> RemoteAccessSnapshot
    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws
    func markFirstDayFinished(coupleID: UUID) async throws
    func markReunionCelebrationSeen(coupleID: UUID) async throws
}

actor LiveAccessGateway: AccessGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadAccessSnapshot() async throws -> RemoteAccessSnapshot {
        let rows: FirstRow<RemoteAccessSnapshot> = try await client.query("access:get_access_snapshot")

        return rows.row ?? RemoteAccessSnapshot(
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: nil
        )
    }

    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws {
        // The backend keys the update on the signed-in user, so an anonymous
        // request would silently mark nothing.
        try await PaeoniaSignedIn.require(isSignedIn)

        try await client.mutation(
            "relationship:mark_relationship_ended_notice_seen",
            args: RelationshipCoupleRequest(coupleID: coupleID)
        )
    }

    func markFirstDayFinished(coupleID: UUID) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)

        try await client.mutation(
            "relationship:mark_first_day_finished",
            args: RelationshipCoupleRequest(coupleID: coupleID)
        )
    }

    func markReunionCelebrationSeen(coupleID: UUID) async throws {
        try await PaeoniaSignedIn.require(isSignedIn)

        try await client.mutation(
            "relationship:mark_reunion_celebration_seen",
            args: RelationshipCoupleRequest(coupleID: coupleID)
        )
    }
}

/// The couple a relationship call is about.
nonisolated private struct RelationshipCoupleRequest: Encodable {
    let coupleID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
    }
}
