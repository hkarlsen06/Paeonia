import Foundation
import StoreKit

/// Deterministic display data used by previews and the developer scenario harness.
/// The production view hierarchy stays intact; only StoreKit's opaque product data
/// and purchase action are replaced.
struct PaywallPresentationOverride {
    let presentation: (PaeoniaBillingPeriod) -> PaywallPresentation
    let purchaseIsEnabled: Bool
    let onPurchase: @MainActor () async -> Bool
}

/// An App Store price: the amount and how to write it in the person's currency.
nonisolated struct PaywallPrice: Equatable, Sendable {
    let amount: Decimal
    let format: Decimal.FormatStyle.Currency

    /// "49 kr" for a whole amount, "49,50 kr" otherwise.
    var text: String {
        var amount = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 0, .plain)
        return rounded == self.amount
            ? self.amount.formatted(format.precision(.fractionLength(0)))
            : self.amount.formatted(format)
    }
}

struct PaywallPresentation {
    let billingPeriod: PaeoniaBillingPeriod
    let product: Product?
    let freeTrial: PaeoniaFreeTrial?
    let isPurchasing: Bool
    let isLoading: Bool
    /// Previews and developer scenarios pass the price directly because they have
    /// no StoreKit product.
    let price: PaywallPrice?

    init(
        billingPeriod: PaeoniaBillingPeriod,
        product: Product?,
        freeTrial: PaeoniaFreeTrial?,
        isPurchasing: Bool,
        isLoading: Bool,
        price: PaywallPrice? = nil
    ) {
        self.billingPeriod = billingPeriod
        self.product = product
        self.freeTrial = freeTrial
        self.isPurchasing = isPurchasing
        self.isLoading = isLoading
        self.price = price ?? product.map { PaywallPrice(amount: $0.price, format: $0.priceFormatStyle) }
    }

    var primaryButtonIsEnabled: Bool {
        product != nil && !isPurchasing && !isLoading
    }

    var hasFreeTrial: Bool {
        freeTrial != nil
    }

    var primaryButtonTitle: LocalizedStringResource {
        if isPurchasing {
            return .paywallCtaPurchasing
        }

        if freeTrial != nil {
            return .paywallCtaFreeTrial
        }

        return .paywallCtaSubscribe
    }

    /// Price, period, and trial in one sentence under the purchase button, as App
    /// Store review expects next to the button that buys.
    var billingDisclosure: String? {
        guard let renewalPrice else {
            return nil
        }
        guard let freeTrial else {
            return String(localized: .paywallDisclosureSubscription(renewalPrice))
        }
        return String(localized: .paywallDisclosureTrial(freeTrial.localizedDurationText, renewalPrice))
    }

    /// For example "49 kr per month".
    private var renewalPrice: String? {
        price.map { "\($0.text) \(String(localized: billingPeriod.perPeriodLabel))" }
    }
}

extension PaeoniaBillingPeriod {
    /// "per month" or "per year".
    var perPeriodLabel: LocalizedStringResource {
        switch self {
        case .monthly:
            .paywallPeriodMonthly
        case .yearly:
            .paywallPeriodYearly
        }
    }

    var planName: LocalizedStringResource {
        switch self {
        case .monthly:
            .paywallBillingMonthly
        case .yearly:
            .paywallBillingYearly
        }
    }
}
