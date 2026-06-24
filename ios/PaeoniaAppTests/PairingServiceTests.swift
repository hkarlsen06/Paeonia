import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

struct PairingInviteCodeTests {
    private let canonicalCode = "01ABCD"

    @Test func normalizationRemovesSeparatorsAndUppercasesCode() throws {
        let rawCode = " 01-ab_cd "

        let normalizedCode = try PairingInviteCode.normalized(rawCode)

        #expect(normalizedCode == canonicalCode)
    }

    @Test func normalizationAcceptsPaeoniaJoinURL() throws {
        let normalizedCode = try PairingInviteCode.normalized(
            "https://paeonia.no/join/01-ab-cd"
        )

        #expect(normalizedCode == canonicalCode)
    }

    @Test func normalizationRejectsWrongLength() {
        #expect(throws: PairingInviteCodeError.invalidLength) {
            try PairingInviteCode.normalized("ABC12")
        }
    }

    @Test func normalizationRejectsInvalidCharacters() {
        #expect(throws: PairingInviteCodeError.invalidCharacters) {
            try PairingInviteCode.normalized("ABC12!")
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
    private let canonicalCode = "01ABCD"

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
            generateInviteCode: { "01-ab-cd" }
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
            codeInput: "https://paeonia.no/join/01-ab-cd"
        )

        #expect(result == preview)
        #expect(await gateway.previewedInviteCode == canonicalCode)
    }

    @Test func acceptInviteNormalizesCodeBeforeCallingGateway() async throws {
        let acceptedCoupleID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let clientID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = PairingClientOperation(
            clientID: clientID,
            clientSequence: 8
        )
        let startedOn = try PairingStartDate(rawValue: "2026-06-24")
        let gateway = FakeSupabasePairingGateway(acceptedCoupleID: acceptedCoupleID)
        let service = SupabasePairingService(gateway: gateway)

        let relationship = try await service.acceptInvite(
            codeInput: "https://paeonia.no/join/01-ab-cd",
            operation: operation,
            startedOn: startedOn
        )

        #expect(relationship.coupleID == acceptedCoupleID)
        #expect(await gateway.acceptedInviteCode == canonicalCode)
        #expect(await gateway.acceptedOperation == operation)
        #expect(await gateway.acceptedStartedOn == startedOn)
    }
}

struct PaywallInviteAcceptanceTests {
    @MainActor
    @Test func acceptingInviteUsesNormalizedCodeAndOperation() async throws {
        let operation = PairingClientOperation(
            id: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientSequence: 9,
            localCreatedAt: Date(timeIntervalSince1970: 40)
        )
        let pairingService = PaywallPairingServiceSpy()
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(operation: operation)
        )

        let accepted = await viewModel.acceptInvite(codeInput: "01-ab-cd")

        #expect(accepted)
        #expect(viewModel.error == nil)
        #expect(await pairingService.acceptedCodeInput == "01ABCD")
        #expect(await pairingService.acceptedOperation == operation)
    }

    @MainActor
    @Test func invalidInviteCodeDoesNotCallPairingService() async {
        let pairingService = PaywallPairingServiceSpy()
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider()
        )

        let accepted = await viewModel.acceptInvite(codeInput: "ABC12")

        #expect(!accepted)
        #expect(viewModel.error == .inviteInvalid)
        #expect(await pairingService.acceptCallCount == 0)
    }
}

struct PairingInviteViewModelTests {
    @MainActor
    @Test func replacingInviteKeepsCurrentInviteUntilNewInviteIsReady() async throws {
        let userID = "11111111-1111-1111-1111-111111111111"
        let currentInvite = try PairingInvite(
            id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            code: "01ABCD",
            joinURL: PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let replacementInvite = try PairingInvite(
            id: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            code: "02BCDE",
            joinURL: PairingJoinURL.make(inviteCode: "02BCDE"),
            expiresAt: Date(timeIntervalSince1970: 30)
        )
        let pairingService = PendingCreatePairingService(invite: replacementInvite)
        let inviteStore = PairingInviteStoreSpy(initialInvite: currentInvite)
        let viewModel = PairingInviteViewModel(
            userID: userID,
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(),
            inviteStore: inviteStore
        )

        let task = Task {
            await viewModel.revokeAndCreateNewInvite()
        }
        await pairingService.waitForCreateToStart()

        #expect(viewModel.invite == currentInvite)
        #expect(viewModel.isRevoking)

        await pairingService.finishCreate()
        await task.value

        #expect(viewModel.invite == replacementInvite)
        #expect(!viewModel.isRevoking)
        #expect(inviteStore.savedInvite == replacementInvite)
    }
}

struct PaywallErrorTests {
    @Test func purchaseConfirmationErrorMessageIncludesServerReason() {
        let error = PaywallError.purchaseNotConfirmed("Local StoreKit transactions cannot be verified by Apple")

        #expect(error.message.contains(String(localized: .paywallErrorPurchaseNotConfirmed)))
        #if DEBUG
        #expect(error.message.contains("Local StoreKit transactions cannot be verified by Apple"))
        #else
        #expect(!error.message.contains("Local StoreKit transactions cannot be verified by Apple"))
        #endif
    }
}

// swiftlint:disable async_without_await
private actor FakeSupabasePairingGateway: SupabasePairingGateway {
    private let createdInviteID: UUID
    private let preview: PairingInvitePreview?
    private let acceptedCoupleID: UUID
    private(set) var createdInviteCode: String?
    private(set) var createdOperation: PairingClientOperation?
    private(set) var createdExpiresAt: Date?
    private(set) var previewedInviteCode: String?
    private(set) var acceptedInviteCode: String?
    private(set) var acceptedOperation: PairingClientOperation?
    private(set) var acceptedStartedOn: PairingStartDate?

    init(
        createdInviteID: UUID = UUID(),
        preview: PairingInvitePreview? = nil,
        acceptedCoupleID: UUID = UUID()
    ) {
        self.createdInviteID = createdInviteID
        self.preview = preview
        self.acceptedCoupleID = acceptedCoupleID
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
        acceptedInviteCode = inviteCode
        acceptedOperation = operation
        acceptedStartedOn = startedOn
        return acceptedCoupleID
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }
}
// swiftlint:enable async_without_await

// swiftlint:disable async_without_await
@MainActor
private final class PaywallStoreKitServiceSpy: PaeoniaStoreKitServicing {
    var products: [Product] { [] }

    func configure(userID: String) {}
    func loadProducts() async throws {}
    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
}

@MainActor
private final class StaticPairingOperationProvider: PairingClientOperationProviding {
    private let operation: PairingClientOperation
    private(set) var makeOperationCallCount = 0

    init(
        operation: PairingClientOperation = PairingClientOperation(
            clientID: UUID(),
            clientSequence: 1
        )
    ) {
        self.operation = operation
    }

    func makeOperation() -> PairingClientOperation {
        makeOperationCallCount += 1
        return operation
    }
}

private actor PaywallPairingServiceSpy: PairingServicing {
    private(set) var acceptCallCount = 0
    private(set) var acceptedCodeInput: String?
    private(set) var acceptedOperation: PairingClientOperation?

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        PairingInvite(
            id: UUID(),
            code: "01ABCD",
            joinURL: try PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: expiresAt
        )
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        nil
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> PairingAcceptedRelationship {
        acceptCallCount += 1
        acceptedCodeInput = codeInput
        acceptedOperation = operation
        return PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }
}
// swiftlint:enable async_without_await

@MainActor
private final class PairingInviteStoreSpy: PairingInviteStoring {
    private let initialInvite: PairingInvite?
    private(set) var savedInvite: PairingInvite?
    private(set) var didClearInvite = false

    init(initialInvite: PairingInvite?) {
        self.initialInvite = initialInvite
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        initialInvite
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        savedInvite = invite
    }

    func clearInvite(for userID: String) {
        didClearInvite = true
    }
}

private actor PendingCreatePairingService: PairingServicing {
    private let invite: PairingInvite
    private var createContinuation: CheckedContinuation<PairingInvite, any Error>?
    private var createStartedContinuation: CheckedContinuation<Void, Never>?

    init(invite: PairingInvite) {
        self.invite = invite
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        return try await withCheckedThrowingContinuation { continuation in
            createContinuation = continuation
            createStartedContinuation?.resume()
            createStartedContinuation = nil
        }
    }

    func waitForCreateToStart() async {
        if createContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            createStartedContinuation = continuation
        }
    }

    func finishCreate() {
        createContinuation?.resume(returning: invite)
        createContinuation = nil
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        nil
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate
    ) async throws -> PairingAcceptedRelationship {
        PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }
}
