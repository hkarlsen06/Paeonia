import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct StreakRestoreViewModelTests {
    @Test func successfulPurchaseReportsCountAndRefreshes() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        var restoredTo: Int?
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            onRestored: { restoredTo = $0 }
        )

        let didPurchase = await viewModel.purchase()

        #expect(didPurchase)
        #expect(viewModel.restoredCount == 30)
        #expect(restoredTo == 30)
        #expect(viewModel.error == nil)
    }

    // MARK: - Paid, but not confirmed

    @Test func serverFailureAfterPaymentSaysThePaymentIsWaiting() async {
        // Apple has already charged by the time the server step fails, so "try again"
        // would be wrong advice.
        let service = FakeStreakRestoreStoreKit(
            result: .failure(.serverConfirmationFailed("Purchase verifier returned HTTP 500."))
        )
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.error == .paidNotConfirmed)
        #expect(viewModel.isAwaitingConfirmation)
        #expect(viewModel.restoredCount == nil)
    }

    @Test func failureBeforePaymentStillAllowsTryingAgain() async {
        let service = FakeStreakRestoreStoreKit(result: .failure(.purchaseFailed))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        _ = await viewModel.purchase()
        #expect(viewModel.error == .purchaseNotConfirmed)

        service.result = .success(30)
        let didRetry = await viewModel.purchase()

        #expect(didRetry)
        #expect(service.redeemCallCount == 2)
    }

    @Test func waitingPaymentIsCheckedAgainInsteadOfBoughtAgain() async {
        let service = FakeStreakRestoreStoreKit(result: .failure(.serverConfirmationFailed(nil)))
        var restoredTo: Int?
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            onRestored: { restoredTo = $0 }
        )

        _ = await viewModel.purchase()
        let stillWaiting = await viewModel.purchase()

        #expect(!stillWaiting)
        #expect(service.redeemCallCount == 1)
        #expect(viewModel.error == .paidNotConfirmed)

        // The server comes back and the unfinished purchase goes through.
        service.recovered = 30
        let didRecover = await viewModel.purchase()

        #expect(didRecover)
        #expect(service.redeemCallCount == 1)
        #expect(viewModel.restoredCount == 30)
        #expect(restoredTo == 30)
        #expect(!viewModel.isAwaitingConfirmation)
        #expect(viewModel.error == nil)
    }

    @Test func windowClosingAfterPaymentStopsFurtherPurchases() async {
        let service = FakeStreakRestoreStoreKit(result: .failure(.streakNotRestorable))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        _ = await viewModel.purchase()
        let secondAttempt = await viewModel.purchase()

        #expect(!secondAttempt)
        #expect(service.redeemCallCount == 1)
        #expect(viewModel.blockingError == .streakNotRestorable)
        #expect(viewModel.error == .streakNotRestorable)
    }

    @Test func purchaseWaitingForApprovalSaysSoAndIsNotRequestedAgain() async {
        let service = FakeStreakRestoreStoreKit(result: .failure(.pendingApproval))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        let firstAttempt = await viewModel.purchase()
        let secondAttempt = await viewModel.purchase()

        #expect(!firstAttempt)
        #expect(!secondAttempt)
        #expect(viewModel.restoredCount == nil)
        #expect(viewModel.error == .waitingForApproval)
        #expect(viewModel.blockingError == .waitingForApproval)
        #expect(service.redeemCallCount == 1)
    }

    @Test func restoredCountOfZeroIsNotACelebration() async {
        let service = FakeStreakRestoreStoreKit(result: .success(0))
        var restoredTo: Int?
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            onRestored: { restoredTo = $0 }
        )

        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.restoredCount == nil)
        #expect(restoredTo == nil)
        #expect(viewModel.error == .paidNotConfirmed)
    }

    @Test func recoveredCountOfZeroIsNotACelebrationAndDoesNotBuyAgain() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30), recovered: 0)
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.restoredCount == nil)
        #expect(viewModel.error == .paidNotConfirmed)
        #expect(service.redeemCallCount == 0)
    }

    // MARK: - Recovery and double taps

    @Test func recoveryOnLoadAppliesPendingRestore() async {
        let service = FakeStreakRestoreStoreKit(result: .success(nil), recovered: 21)
        var restoredTo: Int?
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 21),
            userID: "user",
            storeKitService: service,
            onRestored: { restoredTo = $0 }
        )

        await viewModel.load()

        #expect(viewModel.restoredCount == 21)
        #expect(restoredTo == 21)
    }

    @Test func purchaseAppliesAPendingRestoreInsteadOfBuyingAgain() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30), recovered: 21)
        var restoredTo: Int?
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 21),
            userID: "user",
            storeKitService: service,
            onRestored: { restoredTo = $0 }
        )

        let didRestore = await viewModel.purchase()

        #expect(didRestore)
        #expect(viewModel.restoredCount == 21)
        #expect(restoredTo == 21)
        #expect(service.redeemCallCount == 0)
    }

    @Test func tappingBuyTwiceDuringAPurchaseOnlyBuysOnce() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        service.holdsNextRedeem = true
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        let first = Task { await viewModel.purchase() }
        while service.redeemCallCount == 0 {
            await Task.yield()
        }
        let second = await viewModel.purchase()
        service.releaseHeldRedeem()
        let firstResult = await first.value

        #expect(!second)
        #expect(firstResult)
        #expect(service.redeemCallCount == 1)
        #expect(viewModel.restoredCount == 30)
    }
}

extension CoupleStreak {
    static func restorable(count: Int) -> CoupleStreak {
        CoupleStreak(
            currentCount: 1,
            longestCount: count,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: true,
            restorableCount: count,
            restoreDeadline: .now.addingTimeInterval(3_600)
        )
    }

    /// The streak after the partner bought the restore: nothing is left to restore.
    static func restoredByPartner(count: Int) -> CoupleStreak {
        CoupleStreak(
            currentCount: count,
            longestCount: count,
            lastQualifiedDate: "2026-06-28",
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        )
    }

    /// A broken streak whose restore deadline has passed.
    static func closedOffer() -> CoupleStreak {
        CoupleStreak(
            currentCount: 0,
            longestCount: 30,
            lastQualifiedDate: "2026-06-26",
            restoreAvailable: true,
            restorableCount: 30,
            restoreDeadline: .now.addingTimeInterval(-60)
        )
    }
}

// Protocol stubs are async by conformance, not because they await.
// swiftlint:disable async_without_await
@MainActor
final class FakeStreakRestoreStoreKit: PaeoniaStoreKitServicing {
    enum Outcome {
        case success(Int?)
        case failure(PaeoniaPurchaseError)
    }

    var products: [Product] { [] }

    var result: Outcome
    /// What `recoverPendingStreakRestores()` reports. `nil` means nothing was pending.
    var recovered: Int?
    /// Parks the next purchase inside the App Store so a test can tap again mid-purchase.
    var holdsNextRedeem = false

    private(set) var redeemCallCount = 0
    private var heldRedeem: CheckedContinuation<Void, Never>?

    init(result: Outcome, recovered: Int? = nil) {
        self.result = result
        self.recovered = recovered
    }

    func configure(userID: String) {}

    func loadProducts() async throws {}

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
    func hasActiveFreeTrial() async -> Bool { false }

    func redeemStreakRestore() async throws -> Int? {
        redeemCallCount += 1
        if holdsNextRedeem {
            holdsNextRedeem = false
            await withCheckedContinuation { heldRedeem = $0 }
        }

        switch result {
        case let .success(count):
            return count
        case let .failure(error):
            throw error
        }
    }

    func recoverPendingStreakRestores() async -> Int? { recovered }

    func releaseHeldRedeem() {
        heldRedeem?.resume()
        heldRedeem = nil
    }
}
// swiftlint:enable async_without_await
