import Foundation
import Supabase

protocol SupabasePairingGateway: Actor {
    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID

    func validateInvite(inviteID: UUID, inviteCode: String) async throws -> PairingInviteValidation

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview?

    func rotateInvite(
        currentInviteID: UUID,
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> UUID

    func revokeInvite(id: UUID) async throws -> Bool

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool
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

    func validateInvite(inviteID: UUID, inviteCode: String) async throws -> PairingInviteValidation {
        let validations: [PairingInviteValidation] = try await client
            .rpc(
                "validate_my_pairing_invite",
                params: ValidatePairingInviteRequest(inviteID: inviteID, inviteCode: inviteCode)
            )
            .execute()
            .value

        return validations.first ?? PairingInviteValidation(
            inviteID: nil,
            status: .notFound,
            expiresAt: nil
        )
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

    func rotateInvite(
        currentInviteID: UUID,
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        do {
            return try await client
                .rpc(
                    "rotate_pairing_invite",
                    params: RotatePairingInviteRequest(
                        currentInviteID: currentInviteID,
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

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        // The backend keys the leave on auth.uid(), so an anonymous request would
        // silently leave nothing. Require an active session and let local-first
        // retry handle a restored auth state instead of sending it unsigned.
        _ = try await client.auth.session

        return try await client
            .rpc(
                "leave_relationship",
                params: LeaveRelationshipRequest(operation: operation)
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

nonisolated private struct ValidatePairingInviteRequest: Encodable {
    let inviteID: UUID
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case inviteID = "p_invite_id"
        case inviteCode = "p_invite_code"
    }
}

nonisolated private struct RotatePairingInviteRequest: Encodable {
    let currentInviteID: UUID
    let inviteCode: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let expiresAt: Date

    init(
        currentInviteID: UUID,
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) {
        self.currentInviteID = currentInviteID
        self.inviteCode = inviteCode
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case currentInviteID = "p_current_invite_id"
        case inviteCode = "p_invite_code"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case expiresAt = "p_expires_at"
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

nonisolated private struct LeaveRelationshipRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(operation: PairingClientOperation) {
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}
