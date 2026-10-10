import Foundation

protocol PairingGateway: Actor {
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
        startedOn: PairingStartDate?
    ) async throws -> UUID

    func revokeInvite(id: UUID) async throws -> Bool

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool
}

actor LivePairingGateway: PairingGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        do {
            return try await client.mutation(
                "pairing:create_pairing_invite",
                args: CreatePairingInviteRequest(
                    inviteCode: inviteCode,
                    operation: operation,
                    expiresAt: expiresAt
                )
            )
        } catch where Self.isInviteCodeCollision(error) {
            throw PairingInviteCreationError.inviteCodeCollision
        }
    }

    func validateInvite(inviteID: UUID, inviteCode: String) async throws -> PairingInviteValidation {
        let validations: [PairingInviteValidation] = try await client.mutation(
            "pairing:validate_my_pairing_invite",
            args: ValidatePairingInviteRequest(inviteID: inviteID, inviteCode: inviteCode)
        )

        return validations.first ?? PairingInviteValidation(
            inviteID: nil,
            status: .notFound,
            expiresAt: nil
        )
    }

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview? {
        let previews: [PairingInvitePreview] = try await client.mutation(
            "pairing:preview_pairing_invite",
            args: PreviewPairingInviteRequest(inviteCode: inviteCode)
        )

        return previews.first
    }

    func rotateInvite(
        currentInviteID: UUID,
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        do {
            return try await client.mutation(
                "pairing:rotate_pairing_invite",
                args: RotatePairingInviteRequest(
                    currentInviteID: currentInviteID,
                    inviteCode: inviteCode,
                    operation: operation,
                    expiresAt: expiresAt
                )
            )
        } catch where Self.isInviteCodeCollision(error) {
            throw PairingInviteCreationError.inviteCodeCollision
        }
    }

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> UUID {
        try await client.mutation(
            "pairing:accept_pairing_invite",
            args: AcceptPairingInviteRequest(
                inviteCode: inviteCode,
                operation: operation,
                startedOn: startedOn
            )
        )
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        try await client.mutation(
            "pairing:revoke_pairing_invite",
            args: RevokePairingInviteRequest(inviteID: id)
        )
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        // The backend keys the leave on the signed-in user, so an anonymous request
        // would silently leave nothing. Require a session and let local-first
        // retry handle a restored auth state instead of sending it unsigned.
        try await PaeoniaSignedIn.require(isSignedIn)

        return try await client.mutation(
            "relationship:leave_relationship",
            args: LeaveRelationshipRequest(operation: operation)
        )
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
    let startedOn: String?

    init(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) {
        self.inviteCode = inviteCode
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.startedOn = startedOn?.rawValue
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
