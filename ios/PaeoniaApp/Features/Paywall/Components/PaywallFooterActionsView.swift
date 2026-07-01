import SwiftUI

struct PaywallFooterActionsView: View {
    let isPurchasing: Bool
    let isLoading: Bool
    let showsUnpair: Bool
    let isLeavingRelationship: Bool
    let onRestorePurchases: () -> Void
    let onSignOut: () -> Void
    let onRequestUnpair: () -> Void
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
            Text(.paywallRestorePurchases)
                .font(PaeoniaTypography.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.paeoniaAccentPrimary)
        .disabled(isPurchasing || isLoading)
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
                deleteButton
            }

            VStack(spacing: 0) {
                signOutButton
                if showsUnpair {
                    unpairButton
                }
                deleteButton
            }
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextTertiary)
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
