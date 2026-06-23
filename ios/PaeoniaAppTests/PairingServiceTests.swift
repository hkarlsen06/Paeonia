import Foundation
import Testing
@testable import PaeoniaApp

struct PairingInviteCodeTests {
    private let canonicalCode = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    @Test func normalizationRemovesSeparatorsAndUppercasesCode() throws {
        let rawCode = " 0123-4567 89ab_cdef-ghjk mnpq-rstv wxyz "

        let normalizedCode = try PairingInviteCode.normalized(rawCode)

        #expect(normalizedCode == canonicalCode)
    }

    @Test func normalizationAcceptsPaeoniaJoinURL() throws {
        let normalizedCode = try PairingInviteCode.normalized(
            "https://paeonia.no/join/0123-4567-89ab-cdef-ghjk-mnpq-rstv-wxyz"
        )

        #expect(normalizedCode == canonicalCode)
    }

    @Test func normalizationRejectsWrongLength() {
        #expect(throws: PairingInviteCodeError.invalidLength) {
            try PairingInviteCode.normalized("ABC123")
        }
    }

    @Test func normalizationRejectsInvalidCharacters() {
        #expect(throws: PairingInviteCodeError.invalidCharacters) {
            try PairingInviteCode.normalized("0123456789ABCDEFGHJKMNPQRSTVWXY!")
        }
    }

    @Test func generatedCodeUsesCanonicalShape() throws {
        let code = PairingInviteCode.generate()

        #expect(code.count == PairingInviteCode.length)
        #expect(try PairingInviteCode.normalized(code) == code)
    }

    @Test func joinURLUsesCanonicalPublicDomainAndCodePath() throws {
        let url = try PairingJoinURL.make(inviteCode: canonicalCode.lowercased())

        #expect(url.absoluteString == "https://paeonia.no/join/\(canonicalCode)")
    }
}

struct SupabasePairingServiceTests {
    private let canonicalCode = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    @Test func createInviteUsesGeneratedCodeAndReturnsJoinURL() async throws {
        let inviteID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let clientID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operationID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let operation = PairingClientOperation(
            id: operationID,
            clientID: clientID,
            clientSequence: 7,
            localCreatedAt: Date(timeIntervalSince1970: 10)
        )
        let expiresAt = Date(timeIntervalSince1970: 20)
        let gateway = FakeSupabasePairingGateway(createdInviteID: inviteID)
        let service = SupabasePairingService(
            gateway: gateway,
            generateInviteCode: { "0123-4567-89ab-cdef-ghjk-mnpq-rstv-wxyz" }
        )

        let invite = try await service.createInvite(
            operation: operation,
            expiresAt: expiresAt
        )

        #expect(invite.id == inviteID)
        #expect(invite.code == canonicalCode)
        #expect(invite.joinURL.absoluteString == "https://paeonia.no/join/\(canonicalCode)")
        #expect(invite.expiresAt == expiresAt)
        #expect(await gateway.createdInviteCode == canonicalCode)
        #expect(await gateway.createdOperation == operation)
        #expect(await gateway.createdExpiresAt == expiresAt)
    }

    @Test func previewInviteNormalizesPastedJoinURLBeforeCallingGateway() async throws {
        let preview = PairingInvitePreview(
            inviteID: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            inviterUserID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            inviterDisplayName: "Alex",
            expiresAt: Date(timeIntervalSince1970: 30),
            hasSafetyWarning: false
        )
        let gateway = FakeSupabasePairingGateway(preview: preview)
        let service = SupabasePairingService(gateway: gateway)

        let result = try await service.previewInvite(
            codeInput: "https://paeonia.no/join/0123-4567-89ab-cdef-ghjk-mnpq-rstv-wxyz"
        )

        #expect(result == preview)
        #expect(await gateway.previewedInviteCode == canonicalCode)
    }
}

// swiftlint:disable async_without_await
private actor FakeSupabasePairingGateway: SupabasePairingGateway {
    private let createdInviteID: UUID
    private let preview: PairingInvitePreview?
    private(set) var createdInviteCode: String?
    private(set) var createdOperation: PairingClientOperation?
    private(set) var createdExpiresAt: Date?
    private(set) var previewedInviteCode: String?

    init(
        createdInviteID: UUID = UUID(),
        preview: PairingInvitePreview? = nil
    ) {
        self.createdInviteID = createdInviteID
        self.preview = preview
    }

    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        createdInviteCode = inviteCode
        createdOperation = operation
        createdExpiresAt = expiresAt
        return createdInviteID
    }

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview? {
        previewedInviteCode = inviteCode
        return preview
    }

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> UUID {
        UUID()
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }
}
// swiftlint:enable async_without_await
