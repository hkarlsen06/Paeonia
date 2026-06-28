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
}

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

    private let result: Outcome
    private let recovered: Int?

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

    func redeemStreakRestore() async throws -> Int? {
        switch result {
        case let .success(count):
            return count
        case let .failure(error):
            throw error
        }
    }

    func recoverPendingStreakRestores() async -> Int? { recovered }
}
// swiftlint:enable async_without_await
