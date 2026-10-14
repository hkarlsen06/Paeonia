import StoreKit
import SwiftUI

/// Shown instead of the app when Paeonia banned this account. The person can
/// email support, stop paying, log out, or delete the account. Nothing else
/// works for them, because the server refuses every other request.
struct AccountClosedView: View {
    let isWorking: Bool
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var isManagingSubscription = false
    @State private var isConfirmingDelete = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    private static let supportEmail = URL(string: "mailto:support@paeonia.no")

    var body: some View {
        ScrollView {
            notice
                .padding(.top, PaeoniaSpacing.space40)
                .padding(.bottom, PaeoniaSpacing.space24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .padding(.top, PaeoniaSpacing.space12)
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .alert(Text(.authDeleteAccountConfirmTitle), isPresented: $isConfirmingDelete) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }
            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
        }
        .accessibilityIdentifier("auth.accountClosed")
    }

    private var notice: some View {
        VStack(spacing: PaeoniaSpacing.space20) {
            Image(systemName: "lock.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.authAccountClosedTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(.authAccountClosedMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .padding(.horizontal, PaeoniaSpacing.space24)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if let supportEmail = Self.supportEmail {
                Link(destination: supportEmail) {
                    Text(.authAccountClosedEmailSupport)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
            }

            Button {
                isManagingSubscription = true
            } label: {
                Text(.authAccountClosedManageSubscription)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())

            HStack(spacing: PaeoniaSpacing.space12) {
                Button(action: onSignOut) {
                    accountActionLabel(.settingsAccountLogoutButton)
                }

                Text(verbatim: "·")
                    .accessibilityHidden(true)

                Button {
                    isConfirmingDelete = true
                } label: {
                    accountActionLabel(.authDeleteAccountButton)
                }
            }
            .buttonStyle(.plain)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
        }
        .disabled(isWorking)
    }

    private func accountActionLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
    }
}

#Preview {
    RootBrandedFrame {
        AccountClosedView(isWorking: false, onSignOut: {}, onDeleteAccount: {})
    }
    .preferredColorScheme(.dark)
}
