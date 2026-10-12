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

    @Test func cancelledPurchaseLeavesOfferOpen() async {
        let service = FakeStreakRestoreStoreKit(result: .success(nil))
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
        #expect(viewModel.error == nil)
    }

    @Test func windowClosedMapsToNotRestorableError() async {
        let service = FakeStreakRestoreStoreKit(result: .failure(.streakNotRestorable))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.error == .streakNotRestorable)
    }

    @Test func linkedToAnotherAccountSurfacesAsPurchaseLinkedError() async {
        let service = FakeStreakRestoreStoreKit(result: .failure(.purchaseLinkedToAnotherAccount))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        _ = await viewModel.purchase()

        #expect(viewModel.error == .purchaseLinkedToAnotherAccount)
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

        // Ask to Buy used to look like a cancel: nothing on screen changed.
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

    // MARK: - Service error mapping

    /// Apple has charged before the server step runs. A lost connection there used
    /// to read as "didn't go through" and left Buy enabled, inviting a second charge.
    @Test func lostConnectionAfterPaymentCountsAsPaidButNotConfirmed() {
        let mapped = PaeoniaStoreKitService.streakRestoreConfirmationError(from: URLError(.networkConnectionLost))

        #expect(mapped == .serverConfirmationFailed(nil))
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(from: PaeoniaPurchaseError.streakNotRestorable)
                == .streakNotRestorable
        )
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(
                from: PaeoniaConvexError.server(code: "no_streak_to_restore", message: "No streak is available to restore")
            ) == .streakNotRestorable
        )
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(
                from: PaeoniaConvexError.server(
                    code: "purchase_linked_to_another_account",
                    message: "Apple transaction belongs to a different user"
                )
            ) == .purchaseLinkedToAnotherAccount
        )
        #expect(
            PaeoniaStoreKitService.streakRestoreConfirmationError(
                from: PaeoniaConvexError.server(code: "purchase_not_saved", message: "Could not restore your streak")
            ) == .serverConfirmationFailed("Could not restore your streak")
        )
    }

    /// A paid restore that failed to confirm used to look the same as "nothing
    /// pending", so a reopened sheet could sell a second one.
    @Test func unconfirmedPaidRestoreIsReportedAsPending() async {
        let pending = PaeoniaStoreKitService.pendingRestoreCount(nil, afterFailure: URLError(.timedOut))
        #expect(pending == 0)
        #expect(PaeoniaStoreKitService.pendingRestoreCount(21, afterFailure: URLError(.timedOut)) == 21)
        #expect(
            PaeoniaStoreKitService.pendingRestoreCount(nil, afterFailure: PaeoniaPurchaseError.streakNotRestorable)
                == nil
        )

        // The sheet then waits for the first payment instead of buying again.
        let service = FakeStreakRestoreStoreKit(result: .success(30), recovered: pending)
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )
        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.error == .paidNotConfirmed)
        #expect(service.redeemCallCount == 0)
    }

    // MARK: - Stale sheet

    @Test func partnerRestoringFirstStopsThePurchase() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            latestStreak: { .restoredByPartner(count: 31) }
        )

        let didPurchase = await viewModel.purchase()
        let secondAttempt = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(!secondAttempt)
        #expect(viewModel.error == .streakAlreadyBack)
        #expect(service.redeemCallCount == 0)
    }

    @Test func offerThatClosedSinceOpeningStopsThePurchase() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            latestStreak: { .closedOffer() }
        )

        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.error == .streakExpired)
        #expect(service.redeemCallCount == 0)
    }

    @Test func offerThatIsStillOpenIsBoughtAsUsual() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            latestStreak: { .restorable(count: 30) }
        )

        let didPurchase = await viewModel.purchase()

        #expect(didPurchase)
        #expect(service.redeemCallCount == 1)
    }

    @Test func unreadableLatestStreakDoesNotStopThePurchase() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service,
            latestStreak: { nil }
        )

        let didPurchase = await viewModel.purchase()

        #expect(didPurchase)
        #expect(service.redeemCallCount == 1)
    }

    // MARK: - Price loading

    @Test func purchaseTriesLoadingThePriceFirst() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        _ = await viewModel.purchase()

        #expect(service.loadProductsCallCount == 1)
        #expect(service.redeemCallCount == 1)
    }

    @Test func failedPriceLoadStopsThePurchaseWithAPriceMessage() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        service.loadProductsError = FakeOfflineError()
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        let didPurchase = await viewModel.purchase()

        #expect(!didPurchase)
        #expect(viewModel.error == .productsUnavailable)
        #expect(service.redeemCallCount == 0)
        // Nothing was charged, so the person can simply try again.
        #expect(viewModel.blockingError == nil)
    }

    @Test func failedPriceLoadOnOpenOffersAReload() async {
        let service = FakeStreakRestoreStoreKit(result: .success(30))
        service.loadProductsError = FakeOfflineError()
        let viewModel = StreakRestoreViewModel(
            streak: .restorable(count: 30),
            userID: "user",
            storeKitService: service
        )

        await viewModel.load()

        #expect(viewModel.hasFinishedLoadingProducts)
        #expect(viewModel.error == .productsUnavailable)
        #expect(viewModel.needsPriceRetry)

        service.loadProductsError = nil
        await viewModel.load()

        #expect(service.loadProductsCallCount == 2)
        #expect(!viewModel.needsPriceRetry)
        #expect(viewModel.error == nil)
    }

    // MARK: - Deadline

    @Test func deadlineStateIsUnavailableWithoutDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(StreakRestoreDeadlineState.resolve(deadline: nil, now: now) == .unavailable)
        #expect(StreakRestoreDeadlineState.resolve(deadline: nil, now: now).blocksPurchase)
    }

    @Test func deadlineStateIsActiveBeforeDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)

        let state = StreakRestoreDeadlineState.resolve(
            deadline: now.addingTimeInterval(60),
            now: now
        )

        #expect(state == .active)
        #expect(!state.blocksPurchase)
    }

    @Test func deadlineStateExpiresAtDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(StreakRestoreDeadlineState.resolve(deadline: now, now: now) == .expired)
        #expect(StreakRestoreDeadlineState.resolve(deadline: now.addingTimeInterval(-1), now: now) == .expired)
        #expect(StreakRestoreDeadlineState.resolve(deadline: now, now: now).blocksPurchase)
    }

    @Test func countdownTextCountsDownBySecond() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            StreakRestoreCountdownText.format(
                deadline: now.addingTimeInterval(3_661),
                now: now
            ) == "01:01:01"
        )
        #expect(
            StreakRestoreCountdownText.format(
                deadline: now.addingTimeInterval((27 * 3_600) + 5),
                now: now
            ) == "27:00:05"
        )
    }

    @Test func countdownTextShowsZeroWhenExpired() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(StreakRestoreCountdownText.format(deadline: now, now: now) == "00:00:00")
        #expect(StreakRestoreCountdownText.format(deadline: now.addingTimeInterval(-10), now: now) == "00:00:00")
        #expect(StreakRestoreCountdownText.format(deadline: nil, now: now) == nil)
    }
}

private struct FakeOfflineError: Error {}

private extension CoupleStreak {
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
private final class FakeStreakRestoreStoreKit: PaeoniaStoreKitServicing {
    enum Outcome {
        case success(Int?)
        case failure(PaeoniaPurchaseError)
    }

    var products: [Product] { [] }

    var result: Outcome
    /// What `recoverPendingStreakRestores()` reports. `nil` means nothing was pending.
    var recovered: Int?
    var loadProductsError: (any Error)?
    /// Parks the next purchase inside the App Store so a test can tap again mid-purchase.
    var holdsNextRedeem = false

    private(set) var redeemCallCount = 0
    private(set) var loadProductsCallCount = 0
    private var heldRedeem: CheckedContinuation<Void, Never>?

    init(result: Outcome, recovered: Int? = nil) {
        self.result = result
        self.recovered = recovered
    }

    func configure(userID: String) {}

    func loadProducts() async throws {
        loadProductsCallCount += 1
        if let loadProductsError {
            throw loadProductsError
        }
    }

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }

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
