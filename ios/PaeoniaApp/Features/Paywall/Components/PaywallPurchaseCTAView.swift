import SwiftUI

/// Chooses between the StoreKit purchase action and an actionable product-load
/// retry without making the paywall scene own two separate bottom-bar layouts.
struct PaywallPurchaseCTAView: View {
    let presentation: PaywallPresentation
    let hasProduct: Bool
    let onPurchase: () -> Void
    let onRetry: () -> Void

    @ViewBuilder
    var body: some View {
        if hasProduct {
            PaywallBottomCTAView(
                title: presentation.primaryButtonTitle,
                caption: .paywallCancelAnytime,
                isEnabled: presentation.primaryButtonIsEnabled,
                isBusy: presentation.isPurchasing,
                action: onPurchase
            )
        } else {
            PaywallBottomCTAView(
                title: .paywallProductsRetry,
                caption: nil,
                isEnabled: !presentation.isLoading,
                isBusy: presentation.isLoading,
                action: onRetry
            )
        }
    }
}
