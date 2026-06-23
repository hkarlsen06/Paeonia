import StoreKit
import SwiftUI

struct PaywallView: View {
    @State private var viewModel: PaywallViewModel

    let onPurchaseConfirmed: () -> Void
    let onAcceptInvite: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var isConfirmingDelete = false

    init(
        session: AuthSession?,
        onPurchaseConfirmed: @escaping () -> Void,
        onAcceptInvite: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: PaywallViewModel(userID: session?.id))
        self.onPurchaseConfirmed = onPurchaseConfirmed
        self.onAcceptInvite = onAcceptInvite
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.sectionSpacing) {
            heroCard
            actionCard
            accountActions
        }
        .task {
            await viewModel.loadProducts()
        }
        .confirmationDialog(
            Text(.authDeleteAccountConfirmTitle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
        }
    }

    private var heroCard: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space20) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(.paywallBadge)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaAccentPrimary)

                    Text(.paywallTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.paywallSubtitle)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    PaywallFeatureRow(systemImage: "heart.text.square.fill", title: .paywallFeatureDaily)
                    PaywallFeatureRow(systemImage: "photo.on.rectangle.angled", title: .paywallFeatureMemories)
                    PaywallFeatureRow(systemImage: "rectangle.connected.to.line.below", title: .paywallFeatureWidget)
                }
            }
        }
    }

    private var actionCard: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                billingPicker
                priceBlock
                paywallErrorMessage
                purchaseButton
                restoreButton
                acceptInviteButton
                paywallLinks
            }
        }
    }

    @ViewBuilder
    private var paywallErrorMessage: some View {
        if let error = viewModel.error {
            Text(error.message)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaError)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var purchaseButton: some View {
        Button {
            purchase()
        } label: {
            Label {
                Text(primaryButtonTitle)
            } icon: {
                if viewModel.isPurchasing {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "heart.fill")
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(viewModel.currentProduct == nil || viewModel.isPurchasing || viewModel.isLoading)
    }

    private var restoreButton: some View {
        Button {
            restorePurchases()
        } label: {
            Label {
                Text(.paywallRestorePurchases)
            } icon: {
                Image(systemName: "arrow.clockwise.circle")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .disabled(viewModel.isPurchasing || viewModel.isLoading)
    }

    private var acceptInviteButton: some View {
        Button(action: onAcceptInvite) {
            Label {
                Text(.paywallAcceptInvite)
            } icon: {
                Image(systemName: "link")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
    }

    private var billingPicker: some View {
        Picker(String(localized: .paywallBillingPicker), selection: $viewModel.billingPeriod) {
            Text(.paywallBillingMonthly)
                .tag(PaeoniaBillingPeriod.monthly)
            Text(.paywallBillingYearly)
                .tag(PaeoniaBillingPeriod.yearly)
        }
        .pickerStyle(.segmented)
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                if let product = viewModel.currentProduct {
                    Text(product.displayPrice)
                        .font(PaeoniaTypography.display)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(periodLabel)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                } else {
                    Text(.paywallPriceLoading)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                }
            }

            Text(renewalText)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(.paywallOneSubscription)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountActions: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Button(action: onSignOut) {
                Text(.authSignOutButton)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())

            Button {
                isConfirmingDelete = true
            } label: {
                Text(.authDeleteAccountButton)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        }
    }

    private var paywallLinks: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let subscriptionsURL = Self.subscriptionsURL {
                Link(destination: subscriptionsURL) {
                    Text(.paywallManageSubscription)
                        .font(PaeoniaTypography.caption)
                }
            }

            HStack(spacing: PaeoniaSpacing.space12) {
                if let termsURL = Self.termsURL {
                    Link(destination: termsURL) {
                        Text(.authSignInLegalTerms)
                            .font(PaeoniaTypography.caption)
                    }
                }

                if let privacyURL = Self.privacyURL {
                    Link(destination: privacyURL) {
                        Text(.authSignInLegalPrivacy)
                            .font(PaeoniaTypography.caption)
                    }
                }
            }
        }
        .foregroundStyle(.paeoniaTextTertiary)
    }

    private static let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")
    private static let termsURL = URL(string: "https://paeonia.no/terms")
    private static let privacyURL = URL(string: "https://paeonia.no/privacy")

    private var primaryButtonTitle: LocalizedStringResource {
        if viewModel.isPurchasing {
            return .paywallCtaPurchasing
        }

        return .paywallCtaSubscribe
    }

    private var periodLabel: LocalizedStringResource {
        switch viewModel.billingPeriod {
        case .monthly:
            .paywallPeriodMonthly
        case .yearly:
            .paywallPeriodYearly
        }
    }

    private var renewalText: LocalizedStringResource {
        switch viewModel.billingPeriod {
        case .monthly:
            .paywallRenewalMonthly
        case .yearly:
            .paywallRenewalYearly
        }
    }

    private func purchase() {
        Task {
            let didPurchase = await viewModel.purchaseSelectedProduct()
            if didPurchase {
                onPurchaseConfirmed()
            }
        }
    }

    private func restorePurchases() {
        Task {
            let didRestore = await viewModel.restorePurchases()
            if didRestore {
                onPurchaseConfirmed()
            }
        }
    }
}

private struct PaywallFeatureRow: View {
    let systemImage: String
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PaywallView(
        session: AuthSession(
            id: UUID().uuidString,
            provider: .apple,
            displayName: "Alvilde",
            timeZoneID: "Europe/Oslo",
            profileStatus: .complete
        ),
        onPurchaseConfirmed: {},
        onAcceptInvite: {},
        onSignOut: {},
        onDeleteAccount: {}
    )
    .preferredColorScheme(.dark)
}
