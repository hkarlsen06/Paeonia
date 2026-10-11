import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct PaywallViewModelTests {
    @Test func cancelledPurchaseShowsNoError() async {
        let viewModel = makeViewModel()

        let purchased = await viewModel.runPurchase { false }

        #expect(!purchased)
        #expect(viewModel.error == nil)
        #expect(!viewModel.isPurchasing)
        #expect(!viewModel.purchaseSucceeded)
    }

    @Test func askToBuyShowsCalmWaitingMessage() async {
        let viewModel = makeViewModel()

        _ = await viewModel.runPurchase { throw PaeoniaPurchaseError.pendingApproval }

        #expect(viewModel.error == .purchasePendingApproval)
        #expect(viewModel.error?.isInformational == true)
    }

    @Test func paidButUnconfirmedPurchasePointsToRestore() async {
        let viewModel = makeViewModel()

        _ = await viewModel.runPurchase { throw PaeoniaPurchaseError.serverConfirmationFailed(nil) }

        #expect(viewModel.error == .purchaseNotFinished)
        #expect(viewModel.error?.isInformational == false)
    }

    @Test func successfulPurchaseIsRecorded() async {
        let viewModel = makeViewModel()

        let purchased = await viewModel.runPurchase { true }

        #expect(purchased)
        #expect(viewModel.purchaseSucceeded)
        #expect(viewModel.error == nil)
    }

    /// A double tap used to start two App Store purchases.
    @Test func secondPurchaseWhileFirstRunsIsIgnored() async {
        let viewModel = makeViewModel()
        let gate = HeldStoreCall()

        let first = Task { await viewModel.runPurchase { await gate.run() } }
        await waitUntil { await gate.callCount == 1 }

        let second = await viewModel.runPurchase { await gate.run() }
        let restore = await viewModel.restorePurchases()

        #expect(!second)
        #expect(!restore)
        #expect(await gate.callCount == 1)

        await gate.finish(returning: true)
        #expect(await first.value)
    }

    @Test func restoreCancelledByUserShowsNoError() async {
        let storeKit = PaywallTestStoreKit(restoreResult: .failure(PaeoniaPurchaseError.cancelled))
        let viewModel = makeViewModel(storeKit: storeKit)

        let restored = await viewModel.restorePurchases()

        #expect(!restored)
        #expect(viewModel.error == nil)
        #expect(!viewModel.isRestoring)
    }

    @Test func restoreFindingNothingSaysSo() async {
        let storeKit = PaywallTestStoreKit(restoreResult: .success(false))
        let viewModel = makeViewModel(storeKit: storeKit)

        _ = await viewModel.restorePurchases()

        #expect(viewModel.error == .noPurchasesToRestore)
    }

    /// Restore no longer shares the product-loading flag, so a restore during a
    /// product refresh cannot end the refresh's loading state early.
    @Test func restoreDoesNotTouchProductLoadingState() async {
        let storeKit = PaywallTestStoreKit(restoreResult: .success(true), holdsLoad: true)
        let viewModel = makeViewModel(storeKit: storeKit)

        let loading = Task { await viewModel.loadProducts() }
        await waitUntil { storeKit.isLoadWaiting }

        let restored = await viewModel.restorePurchases()

        #expect(restored)
        #expect(viewModel.isLoading)

        storeKit.finishLoad()
        await loading.value
        #expect(!viewModel.isLoading)
    }

    /// A slow App Store used to keep the whole paywall, including restore, sign
    /// out, and the legal links, behind the loading screen with no end.
    @Test func slowProductLoadStillPresentsAfterDeadline() async {
        let storeKit = PaywallTestStoreKit(restoreResult: .success(false), holdsLoad: true)
        let viewModel = makeViewModel(storeKit: storeKit, deadline: .milliseconds(50))

        let loading = Task { await viewModel.loadProducts() }
        await waitUntil { storeKit.isLoadWaiting }
        #expect(!viewModel.isPresentationReady)

        await waitUntil { viewModel.isPresentationReady }

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.isLoading)

        storeKit.finishLoad()
        await loading.value
        #expect(!viewModel.isLoading)
    }

    @Test func unusableInviteCodeIsFlaggedButNetworkFailureIsNot() async {
        let unavailable = makeViewModel(pairing: PaywallTestPairing(previewResult: .success(nil)))
        _ = await unavailable.previewInvite(codeInput: "ABCD23")
        #expect(unavailable.lastInviteCodeWasUnusable)
        #expect(unavailable.error == .inviteUnavailable)

        let offline = makeViewModel(
            pairing: PaywallTestPairing(previewResult: .failure(URLError(.notConnectedToInternet)))
        )
        _ = await offline.previewInvite(codeInput: "ABCD23")
        #expect(!offline.lastInviteCodeWasUnusable)
        #expect(offline.error == .invitePreviewFailed)
    }

    /// The first accept reached the server and paired the couple, but its answer
    /// was lost. Retrying used to preview again (the used invite now looks gone)
    /// and send a new operation (the couple now exists), so it always failed.
    @Test func retryAfterLostAcceptAnswerReplaysTheSameOperation() async {
        let pairing = LostAnswerPairing()
        let viewModel = PaywallViewModel(
            userID: "user-1",
            storeKitService: PaywallTestStoreKit(restoreResult: .success(false)),
            pairingService: pairing,
            operationProvider: CountingOperationProvider()
        )

        #expect(await viewModel.previewInvite(codeInput: "ABCD23") != nil)
        #expect(await viewModel.acceptPreviewedInvite() == false)
        #expect(viewModel.error == .inviteAcceptFailed)

        #expect(await viewModel.previewInvite(codeInput: "ABCD23") != nil)
        #expect(await viewModel.acceptPreviewedInvite())

        #expect(await pairing.previewCount == 1)
        let operations = await pairing.acceptOperations
        #expect(operations.count == 2)
        #expect(operations.first == operations.last)
    }

    @Test func serverRejectionStartsTheNextAcceptFresh() async {
        let pairing = LostAnswerPairing(firstFailure: .server(code: "22023", message: "pairing invite is expired"))
        let viewModel = PaywallViewModel(
            userID: "user-1",
            storeKitService: PaywallTestStoreKit(restoreResult: .success(false)),
            pairingService: pairing,
            operationProvider: CountingOperationProvider()
        )

        _ = await viewModel.previewInvite(codeInput: "ABCD23")
        _ = await viewModel.acceptPreviewedInvite()
        _ = await viewModel.previewInvite(codeInput: "ABCD23")

        #expect(await pairing.previewCount == 2)
    }

    private func makeViewModel(
        storeKit: PaywallTestStoreKit? = nil,
        pairing: PaywallTestPairing? = nil,
        deadline: Duration = .seconds(5)
    ) -> PaywallViewModel {
        PaywallViewModel(
            userID: "user-1",
            storeKitService: storeKit ?? PaywallTestStoreKit(restoreResult: .success(false)),
            pairingService: pairing ?? PaywallTestPairing(previewResult: .success(nil)),
            operationProvider: PaywallTestOperationProvider(),
            firstPresentationDeadline: deadline
        )
    }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private actor HeldStoreCall {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var callCount = 0

    func run() async -> Bool {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(returning result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

// Fakes implement only what the paywall uses, so unused requirements trap and
// sync bodies need no await.
// swiftlint:disable async_without_await unavailable_function
@MainActor
private final class PaywallTestStoreKit: PaeoniaStoreKitServicing {
    var products: [Product] { [] }
    private let restoreResult: Result<Bool, Error>
    private let holdsLoad: Bool
    private var loadContinuation: CheckedContinuation<Void, Never>?

    init(restoreResult: Result<Bool, Error>, holdsLoad: Bool = false) {
        self.restoreResult = restoreResult
        self.holdsLoad = holdsLoad
    }

    var isLoadWaiting: Bool {
        loadContinuation != nil
    }

    func finishLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func configure(userID: String) {}

    func loadProducts() async throws {
        guard holdsLoad else {
            return
        }
        await withCheckedContinuation { loadContinuation = $0 }
    }

    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? { nil }
    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { try restoreResult.get() }
    func redeemStreakRestore() async throws -> Int? { nil }
    func recoverPendingStreakRestores() async -> Int? { nil }
}

/// Only `previewInvite` is exercised by these tests.
private actor PaywallTestPairing: PairingServicing {
    private let previewResult: Result<PairingInvitePreview?, Error>

    init(previewResult: Result<PairingInvitePreview?, Error>) {
        self.previewResult = previewResult
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        try previewResult.get()
    }

    func createInvite(operation: PairingClientOperation, expiresAt: Date) async throws -> PairingInvite {
        fatalError("unused")
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        fatalError("unused")
    }
}

@MainActor
private final class PaywallTestOperationProvider: PairingClientOperationProviding {
    func makeOperation() -> PairingClientOperation {
        SyncClientOperation(clientID: UUID(), clientSequence: 1)
    }
}

/// Pairs on the first accept but loses the answer (or rejects it, when
/// `firstFailure` is a server error). Like the server, a replay of the first
/// operation returns the stored result, and any other operation fails.
private actor LostAnswerPairing: PairingServicing {
    private let firstFailure: PaeoniaConvexError?
    private var pairedOperation: PairingClientOperation?
    private(set) var previewCount = 0
    private(set) var acceptOperations = [PairingClientOperation]()

    init(firstFailure: PaeoniaConvexError? = nil) {
        self.firstFailure = firstFailure
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        previewCount += 1
        guard pairedOperation == nil else {
            return nil
        }
        return PairingInvitePreview(
            inviteID: UUID(),
            inviterUserID: UUID(),
            inviterDisplayName: "Robin",
            expiresAt: Date().addingTimeInterval(3_600),
            hasSafetyWarning: false
        )
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        acceptOperations.append(operation)
        if let pairedOperation {
            guard pairedOperation == operation else {
                throw PaeoniaConvexError.server(code: "22023", message: "pairing invite is not pending")
            }
            return PairingAcceptedRelationship(coupleID: UUID())
        }
        if let firstFailure, acceptOperations.count == 1 {
            throw firstFailure
        }
        pairedOperation = operation
        throw URLError(.networkConnectionLost)
    }

    func createInvite(operation: PairingClientOperation, expiresAt: Date) async throws -> PairingInvite {
        fatalError("unused")
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        fatalError("unused")
    }
}

/// Hands out a new operation every time, so a reused one is easy to spot.
@MainActor
private final class CountingOperationProvider: PairingClientOperationProviding {
    private var sequence: Int64 = 0

    func makeOperation() -> PairingClientOperation {
        sequence += 1
        return SyncClientOperation(clientID: UUID(), clientSequence: sequence)
    }
}
// swiftlint:enable async_without_await unavailable_function
