import Foundation

typealias PairingInviteCodeGenerator = @Sendable () -> String

enum PairingInviteCreationError: Error, Equatable {
    case inviteCodeCollision
}

protocol PairingServicing: Actor {
    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview?

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> PairingAcceptedRelationship

    func revokeInvite(id: UUID) async throws -> Bool

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool
}

actor SupabasePairingService: PairingServicing {
    private let gateway: any SupabasePairingGateway
    private let generateInviteCode: PairingInviteCodeGenerator
    private let maxCreateInviteAttempts = 3

    init(
        gateway: any SupabasePairingGateway,
        generateInviteCode: @escaping PairingInviteCodeGenerator = PairingInviteCode.generate
    ) {
        self.gateway = gateway
        self.generateInviteCode = generateInviteCode
    }

    static func live() throws -> SupabasePairingService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabasePairingService(gateway: LiveSupabasePairingGateway(client: client))
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        var lastCollision: PairingInviteCreationError?

        for _ in 1...maxCreateInviteAttempts {
            let inviteCode = try PairingInviteCode.normalized(generateInviteCode())

            do {
                let inviteID = try await gateway.createInvite(
                    inviteCode: inviteCode,
                    operation: operation,
                    expiresAt: expiresAt
                )

                return PairingInvite(
                    id: inviteID,
                    code: inviteCode,
                    joinURL: try PairingJoinURL.make(inviteCode: inviteCode),
                    expiresAt: expiresAt
                )
            } catch PairingInviteCreationError.inviteCodeCollision {
                lastCollision = .inviteCodeCollision
            }
        }

        if let lastCollision {
            throw lastCollision
        }

        throw PairingInviteCreationError.inviteCodeCollision
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        let inviteCode = try PairingInviteCode.normalized(codeInput)
        return try await gateway.previewInvite(inviteCode: inviteCode)
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> PairingAcceptedRelationship {
        let inviteCode = try PairingInviteCode.normalized(codeInput)
        let coupleID = try await gateway.acceptInvite(
            inviteCode: inviteCode,
            operation: operation,
            startedOn: startedOn
        )

        return PairingAcceptedRelationship(coupleID: coupleID)
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        try await gateway.revokeInvite(id: id)
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        try await gateway.leaveRelationship(operation: operation)
    }
}
