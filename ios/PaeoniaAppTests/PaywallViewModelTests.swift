import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct PaywallViewModelTests {
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

    private func makeViewModel(
        storeKit: PaywallTestStoreKit? = nil,
        deadline: Duration = .seconds(5)
    ) -> PaywallViewModel {
        PaywallViewModel(
            userID: "user-1",
            storeKitService: storeKit ?? PaywallTestStoreKit(restoreResult: .success(false)),
            pairingService: PaywallTestPairing(),
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
    func hasActiveFreeTrial() async -> Bool { false }
    func redeemStreakRestore() async throws -> Int? { nil }
    func recoverPendingStreakRestores() async -> Int? { nil }
}

/// None of these tests reach the pairing service.
private actor PaywallTestPairing: PairingServicing {
    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        fatalError("unused")
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

// swiftlint:enable async_without_await unavailable_function
