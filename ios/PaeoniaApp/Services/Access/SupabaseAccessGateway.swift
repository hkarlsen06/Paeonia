import Foundation
import Supabase

protocol SupabaseAccessGateway: Actor {
    func loadAccessSnapshot() async throws -> SupabaseAccessSnapshot
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

    func loadAccessSnapshot() async throws -> SupabaseAccessSnapshot {
        let rows: [SupabaseAccessSnapshot] = try await client
            .rpc("get_access_snapshot")
            .execute()
            .value

        return rows.first ?? SupabaseAccessSnapshot(
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: nil
        )
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
