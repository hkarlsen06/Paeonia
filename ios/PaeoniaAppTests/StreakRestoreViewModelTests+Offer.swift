import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
extension StreakRestoreViewModelTests {
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
