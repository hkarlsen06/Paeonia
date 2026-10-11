import SwiftUI

/// The account actions at the bottom of the Me tab: log out, leave the
/// relationship, and delete the account.
///
/// They sit last on the tab, below everything a user opens every day, and each one
/// only opens a centered confirmation. Nothing happens until the user confirms.
struct SettingsAccountSection: View {
    let viewModel: SettingsViewModel
    let authProvider: AuthProvider?
    /// Names the partner in the leave confirmation instead of saying "your partner".
    let partnerName: String
    let onLeftRelationship: () -> Void
    let onLogout: () -> Void
    let onDeleteAccount: () -> Void
    /// True while a log-out runs. It sends what is left and can take a few seconds.
    var isLoggingOut = false

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @State private var isConfirmingLogout = false
    @State private var isConfirmingLeave = false
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            SettingsMenuSection(title: .settingsAccountSectionTitle) {
                actionRows
            }

            if let authProviderName {
                Text(.settingsProfileSignedInWith(authProviderName))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
                    .padding(.horizontal, PaeoniaSpacing.space16)
            }
        }
        .alert(Text(.settingsAccountLogoutConfirmTitle), isPresented: $isConfirmingLogout) {
            Button(role: .destructive, action: onLogout) {
                Text(.settingsAccountLogoutButton)
            }
            Button(role: .cancel, action: {}) {
                Text(.commonCancel)
            }
        } message: {
            Text(.settingsAccountLogoutConfirmMessage)
        }
        .alert(Text(.pairingUnpairConfirmTitle(partnerName)), isPresented: $isConfirmingLeave) {
            Button(role: .destructive, action: leaveRelationship) {
                Text(.pairingUnpairConfirmAction)
            }
            Button(role: .cancel, action: {}) {
                Text(.pairingUnpairConfirmCancel)
            }
        } message: {
            Text(.pairingUnpairConfirmMessage(partnerName))
        }
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
    }

    @ViewBuilder
    private var actionRows: some View {
        SettingsActionRow(
            title: .settingsAccountLogoutButton,
            systemImage: "rectangle.portrait.and.arrow.right",
            isBusy: isLoggingOut
        ) {
            isConfirmingLogout = true
        }

        SettingsMenuDivider()

        SettingsActionRow(
            title: .settingsUnpairButton,
            systemImage: "heart.slash.fill",
            isDestructive: true,
            isBusy: viewModel.isLeavingRelationship
        ) {
            isConfirmingLeave = true
        }
        .disabled(isLoggingOut)

        SettingsMenuDivider()

        SettingsActionRow(
            title: .authDeleteAccountButton,
            systemImage: "trash",
            isDestructive: true
        ) {
            isConfirmingDelete = true
        }
        .disabled(viewModel.isLeavingRelationship || isLoggingOut)
    }

    /// Brand names stay unlocalized; only the sentence around them is translated.
    /// Development and unknown sessions show no line rather than leaking internals.
    private var authProviderName: String? {
        switch authProvider {
        case .apple: "Apple"
        case .google: "Google"
        case .development, .unknown, nil: nil
        }
    }

    private func leaveRelationship() {
        Task {
            if await viewModel.leaveRelationship() {
                bannerCenter.dismiss()
                onLeftRelationship()
            }
        }
    }
}
