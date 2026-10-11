import StoreKit
import SwiftUI

/// Subscription management and purchase restore, together on one screen because
/// both answer the same question: what did I pay for, and how do I change it?
struct PurchaseSettingsView: View {
    let viewModel: SettingsViewModel
    /// Lets the root re-resolve access once a restore finds a subscription.
    let onPurchasesRestored: @MainActor @Sendable () async -> Void

    @State private var isManagingSubscription = false

    var body: some View {
        SettingsDetailScreen(title: .settingsPurchasesSectionTitle) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                SettingsMenuSection {
                    // Apple's own sheet, so changing or cancelling never leaves
                    // the app.
                    Button {
                        isManagingSubscription = true
                    } label: {
                        PaeoniaDisclosureRow(
                            title: .paywallManageSubscription,
                            systemImage: "creditcard"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsMenuDivider()

                    SettingsActionRow(
                        title: viewModel.isRestoringPurchases
                            ? .settingsPurchasesRestoring
                            : .paywallRestorePurchases,
                        systemImage: "arrow.clockwise",
                        isBusy: viewModel.isRestoringPurchases,
                        action: restorePurchases
                    )
                }

                Text(.paywallOneSubscription)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .padding(.horizontal, PaeoniaSpacing.space16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
    }

    private func restorePurchases() {
        Task { @MainActor in
            if await viewModel.restorePurchases() {
                await onPurchasesRestored()
            }
        }
    }
}

#Preview {
    NavigationStack {
        PurchaseSettingsView(viewModel: SettingsViewModel(), onPurchasesRestored: {})
    }
    .preferredColorScheme(.dark)
}
