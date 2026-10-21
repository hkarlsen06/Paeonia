import SwiftUI

struct PaywallFooterActionsView: View {
    /// A purchase or restore is talking to the App Store. Account actions wait,
    /// so nobody signs out or deletes the account in the middle of a payment.
    let isBusyWithStore: Bool
    let isRestoring: Bool
    let showsUnpair: Bool
    let isLeavingRelationship: Bool
    let onRestorePurchases: () -> Void
    let onSignOut: () -> Void
    let onRequestUnpair: () -> Void
    /// Opens "Download my data". Everyone has the right to their data, so it sits
    /// here for people who cannot reach the rest of the app without a subscription.
    let onRequestDataExport: () -> Void
    let onRequestDeleteAccount: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Divider()
                .background(.paeoniaSurfacePressed)
                .padding(.bottom, PaeoniaSpacing.space4)
            restoreButton
            PaeoniaLegalLinksView()
            accountActions
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
    }

    private var restoreButton: some View {
        Button(action: onRestorePurchases) {
            HStack(spacing: PaeoniaSpacing.space8) {
                if isRestoring {
                    ProgressView()
                        .tint(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)
                }
                Text(isRestoring ? .settingsPurchasesRestoring : .paywallRestorePurchases)
                    .font(PaeoniaTypography.bodyEmphasis)
            }
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.paeoniaAccentPrimary)
        .disabled(isBusyWithStore)
    }

    private var accountActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                signOutButton
                if showsUnpair {
                    separator
                    unpairButton
                }
                separator
                dataExportButton
                separator
                deleteButton
            }

            VStack(spacing: 0) {
                signOutButton
                if showsUnpair {
                    unpairButton
                }
                dataExportButton
                deleteButton
            }
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextTertiary)
        .disabled(isBusyWithStore)
    }

    private var signOutButton: some View {
        Button(action: onSignOut) {
            footerLabel(.authSignOutButton)
        }
        .buttonStyle(.plain)
    }

    private var unpairButton: some View {
        Button(action: onRequestUnpair) {
            footerLabel(.paywallUnpairButton)
        }
        .buttonStyle(.plain)
        .disabled(isLeavingRelationship)
    }

    private var dataExportButton: some View {
        Button(action: onRequestDataExport) {
            footerLabel(.privacySafetyDataExportTitle)
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onRequestDeleteAccount) {
            footerLabel(.authDeleteAccountButton)
        }
        .buttonStyle(.plain)
    }

    /// A footer link/label sized for an easy 44pt tap target, matching the
    /// sign-in screen's link cluster.
    private func footerLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
    }
}
