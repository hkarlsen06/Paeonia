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
}
