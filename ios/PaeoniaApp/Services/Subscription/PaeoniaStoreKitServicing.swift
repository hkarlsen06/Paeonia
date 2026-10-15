import StoreKit

@MainActor
protocol PaeoniaStoreKitServicing: AnyObject {
    var products: [Product] { get }

    func configure(userID: String)
    func loadProducts() async throws
    /// Returns the configured free trial only when StoreKit says the current
    /// App Store account is eligible for the subscription group's introductory
    /// offer. A configured offer alone is not proof that this user can redeem it.
    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial?
    func product(for productID: PaeoniaSubscriptionProductID) -> Product?
    func product(for productID: PaeoniaConsumableProductID) -> Product?
    /// `true` once the server confirmed the purchase, `false` when the user
    /// cancelled. Throws `PaeoniaPurchaseError.pendingApproval` for Ask to Buy.
    func purchase(_ product: Product) async throws -> Bool
    /// `true` when a subscription for this account was confirmed. Throws
    /// `PaeoniaPurchaseError.cancelled` when the user closes the App Store sheet.
    func restorePurchases() async throws -> Bool
    /// Buys the streak-restore consumable and asks the server to bring the streak
    /// back. Returns the restored streak length, or `nil` if the user cancelled.
    func redeemStreakRestore() async throws -> Int?
    /// Re-applies any streak-restore purchase that was paid for but never
    /// confirmed (e.g. the app died mid-flow). Idempotent on the server. Returns
    /// the restored streak length if one was recovered.
    @discardableResult
    func recoverPendingStreakRestores() async -> Int?
}

extension PaeoniaStoreKitServicing {
    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? {
        guard let subscription = product(for: productID)?.subscription,
              let introductoryOffer = subscription.introductoryOffer,
              let configuredTrial = PaeoniaFreeTrial(offer: introductoryOffer)
        else {
            return nil
        }

        let isEligible = await subscription.isEligibleForIntroOffer
        return PaeoniaStoreKitOfferEligibility.freeTrial(
            configuredOffer: configuredTrial,
            isEligible: isEligible
        )
    }
}

/// Small value-level policy kept separate from StoreKit's opaque `Product` so the
/// distinction between a configured and an eligible offer has a focused regression
/// test. Production eligibility still comes directly from StoreKit above.
nonisolated enum PaeoniaStoreKitOfferEligibility {
    static func freeTrial(
        configuredOffer: PaeoniaFreeTrial?,
        isEligible: Bool
    ) -> PaeoniaFreeTrial? {
        guard isEligible else {
            return nil
        }
        return configuredOffer
    }
}
