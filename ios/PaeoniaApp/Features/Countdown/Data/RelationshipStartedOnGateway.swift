import Foundation

nonisolated protocol RelationshipStartedOnGateway: Actor {
    func setStartedOn(
        _ startedOn: PairingStartDate,
        operation: SyncClientOperation
    ) async throws -> String
}

actor LiveRelationshipStartedOnGateway: RelationshipStartedOnGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func setStartedOn(
        _ startedOn: PairingStartDate,
        operation: SyncClientOperation
    ) async throws -> String {
        // The backend authorizes with the session. Fail locally when auth is absent so
        // the durable pending operation retries after the session is restored.
        try await PaeoniaSignedIn.require(isSignedIn)

        return try await client.mutation(
            "relationship:set_couple_started_on",
            args: SetRelationshipStartedOnRequest(startedOn: startedOn, operation: operation)
        )
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
