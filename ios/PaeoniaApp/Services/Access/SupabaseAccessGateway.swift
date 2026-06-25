import Foundation
import Supabase

protocol SupabaseAccessGateway: Actor {
    func loadMyEntitlement() async throws -> SupabaseUserEntitlement?
    func loadMyCoupleEntitlement() async throws -> SupabaseCoupleEntitlement?
    func loadCurrentRelationshipState() async throws -> SupabaseRelationshipState?
    func loadRelationshipSyncEvents(
        after cursor: SyncCursor,
        limit: Int
    ) async throws -> [SupabaseRelationshipSyncEvent]
}

actor LiveSupabaseAccessGateway: SupabaseAccessGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadMyEntitlement() async throws -> SupabaseUserEntitlement? {
        let rows: [SupabaseUserEntitlement] = try await client
            .rpc("get_my_entitlement")
            .execute()
            .value

        return rows.first
    }

    func loadMyCoupleEntitlement() async throws -> SupabaseCoupleEntitlement? {
        let rows: [SupabaseCoupleEntitlement] = try await client
            .rpc("get_my_couple_entitlement")
            .execute()
            .value

        return rows.first
    }

    func loadCurrentRelationshipState() async throws -> SupabaseRelationshipState? {
        let rows: [SupabaseRelationshipState] = try await client
            .rpc("get_current_relationship_state")
            .execute()
            .value

        return rows.first
    }

    func loadRelationshipSyncEvents(
        after cursor: SyncCursor,
        limit: Int
    ) async throws -> [SupabaseRelationshipSyncEvent] {
        var query = client
            .from("relationship_sync_events")
            .select()

        if let createdAt = cursor.updatedAt {
            if let tieID = cursor.tieID {
                let timestamp = Self.postgrestTimestamp(createdAt)
                query = query.or(
                    "created_at.gt.\(timestamp),and(created_at.eq.\(timestamp),id.gt.\(tieID.uuidString))"
                )
            } else {
                query = query.gt("created_at", value: createdAt)
            }
        }

        return try await query
            .order("created_at", ascending: true)
            .order("id", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    private static func postgrestTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
