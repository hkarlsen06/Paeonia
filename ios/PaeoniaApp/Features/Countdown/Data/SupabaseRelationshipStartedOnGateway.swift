import Foundation
import Supabase

nonisolated protocol SupabaseRelationshipStartedOnGateway: Actor {
    func setStartedOn(
        _ startedOn: PairingStartDate,
        operation: SyncClientOperation
    ) async throws -> String
}

actor LiveSupabaseRelationshipStartedOnGateway: SupabaseRelationshipStartedOnGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func setStartedOn(
        _ startedOn: PairingStartDate,
        operation: SyncClientOperation
    ) async throws -> String {
        // The RPC authorizes with auth.uid(). Fail locally when auth is absent so
        // the durable pending operation retries after the session is restored.
        _ = try await client.auth.session

        return try await client
            .rpc(
                "set_couple_started_on",
                params: SetRelationshipStartedOnRequest(
                    startedOn: startedOn,
                    operation: operation
                )
            )
            .execute()
            .value
    }
}

nonisolated private struct SetRelationshipStartedOnRequest: Encodable {
    let startedOn: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(startedOn: PairingStartDate, operation: SyncClientOperation) {
        self.startedOn = startedOn.rawValue
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case startedOn = "p_started_on"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
