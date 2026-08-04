import SwiftUI

/// Subscription management and purchase restore, together on one screen because
/// both answer the same question: what did I pay for, and how do I change it?
struct PurchaseSettingsView: View {
    let viewModel: SettingsViewModel
    /// Lets the root re-resolve access once a restore finds a subscription.
    let onPurchasesRestored: @MainActor @Sendable () async -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsDetailScreen(title: .settingsPurchasesSectionTitle) {
            SettingsMenuSection {
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                } label: {
                    PaeoniaDisclosureRow(
                        title: .paywallManageSubscription,
                        systemImage: "creditcard",
                        accessory: .externalLink
                    )
                }
                .buttonStyle(.plain)

                SettingsMenuDivider()

                Button(action: restorePurchases) {
                    restoreRow
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRestoringPurchases)
            }
        }
    }

    /// An action row: the same leading-icon shape as the disclosure row above it,
    /// but with a spinner instead of a chevron while the restore is running.
    private var restoreRow: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "arrow.clockwise")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: PaeoniaSpacing.space24)
                .accessibilityHidden(true)

            Text(
                viewModel.isRestoringPurchases
                    ? .settingsPurchasesRestoring
                    : .paywallRestorePurchases
            )
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isRestoringPurchases {
                ProgressView()
                    .tint(.paeoniaTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
        .contentShape(Rectangle())
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
