import Foundation
import Supabase

protocol SupabasePairingGateway: Actor {
    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview?

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> UUID

    func revokeInvite(id: UUID) async throws -> Bool
}

actor LiveSupabasePairingGateway: SupabasePairingGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        do {
            return try await client
                .rpc(
                    "create_pairing_invite",
                    params: CreatePairingInviteRequest(
                        inviteCode: inviteCode,
                        operation: operation,
                        expiresAt: expiresAt
                    )
                )
                .execute()
                .value
        } catch where Self.isInviteCodeCollision(error) {
            throw PairingInviteCreationError.inviteCodeCollision
        }
    }

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview? {
        let previews: [PairingInvitePreview] = try await client
            .rpc(
                "preview_pairing_invite",
                params: PreviewPairingInviteRequest(inviteCode: inviteCode)
            )
            .execute()
            .value

        return previews.first
    }

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> UUID {
        try await client
            .rpc(
                "accept_pairing_invite",
                params: AcceptPairingInviteRequest(
                    inviteCode: inviteCode,
                    operation: operation,
                    startedOn: startedOn
                )
            )
            .execute()
            .value
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        try await client
            .rpc(
                "revoke_pairing_invite",
                params: RevokePairingInviteRequest(inviteID: id)
            )
            .execute()
            .value
    }

    private static func isInviteCodeCollision(_ error: any Error) -> Bool {
        String(describing: error).contains("pairing_invite_secrets_code_hash_unique")
    }
}

nonisolated private struct CreatePairingInviteRequest: Encodable {
    let inviteCode: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let expiresAt: Date

    init(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) {
        self.inviteCode = inviteCode
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case inviteCode = "p_invite_code"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case expiresAt = "p_expires_at"
    }
}

nonisolated private struct PreviewPairingInviteRequest: Encodable {
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "p_invite_code"
    }
}

nonisolated private struct AcceptPairingInviteRequest: Encodable {
    let inviteCode: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let startedOn: String

    init(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) {
        self.inviteCode = inviteCode
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.startedOn = startedOn.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case inviteCode = "p_invite_code"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case startedOn = "p_started_on"
    }
}

nonisolated private struct RevokePairingInviteRequest: Encodable {
    let inviteID: UUID

    enum CodingKeys: String, CodingKey {
        case inviteID = "p_invite_id"
    }
}
