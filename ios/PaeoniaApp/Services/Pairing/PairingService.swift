import Foundation

typealias PairingInviteCodeGenerator = @Sendable () -> String

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
}

actor SupabasePairingService: PairingServicing {
    private let gateway: any SupabasePairingGateway
    private let generateInviteCode: PairingInviteCodeGenerator

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
        let inviteCode = try PairingInviteCode.normalized(generateInviteCode())
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
}
