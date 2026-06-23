import Supabase

protocol SupabaseAccessGateway: Actor {
    func loadMyEntitlement() async throws -> SupabaseUserEntitlement?
    func loadMyCoupleEntitlement() async throws -> SupabaseCoupleEntitlement?
    func loadCurrentRelationshipState() async throws -> SupabaseRelationshipState?
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
}
