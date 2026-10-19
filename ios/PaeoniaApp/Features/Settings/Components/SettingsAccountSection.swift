import SwiftUI

/// The account actions on the profile screen: log out, leave the relationship,
/// and delete the account.
///
/// They sit one step away from the Us tab, below the name and photo, and each one
/// only opens a centered confirmation. Nothing happens until the user confirms.
/// The footer names the sign-in provider.
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
        Section {
            // Each confirmation sits on its own row. On the section it would land
            // on every row.
            logoutRow
            leaveRow
            deleteRow
        } header: {
            Text(.settingsAccountSectionTitle)
        } footer: {
            if let authProviderName {
                Text(.settingsProfileSignedInWith(authProviderName))
            }
        }
    }

    private var logoutRow: some View {
        SettingsActionRow(
            title: .settingsAccountLogoutButton,
            systemImage: "rectangle.portrait.and.arrow.right",
            isBusy: isLoggingOut
        ) {
            isConfirmingLogout = true
        }
        .accessibilityIdentifier("settings.account.logout")
        .alert(Text(.settingsAccountLogoutConfirmTitle), isPresented: $isConfirmingLogout) {
            Button(role: .destructive, action: onLogout) {
                Text(.settingsAccountLogoutButton)
            }
            .accessibilityIdentifier("settings.account.logout.confirm")
            Button(role: .cancel, action: {}) {
                Text(.commonCancel)
            }
        } message: {
            Text(.settingsAccountLogoutConfirmMessage)
        }
    }

    private var leaveRow: some View {
        SettingsActionRow(
            title: .settingsUnpairButton,
            systemImage: "heart.slash.fill",
            role: .destructive,
            isBusy: viewModel.isLeavingRelationship
        ) {
            isConfirmingLeave = true
        }
        .disabled(isLoggingOut)
        .accessibilityIdentifier("settings.account.leave")
        .alert(Text(.pairingUnpairConfirmTitle(partnerName)), isPresented: $isConfirmingLeave) {
            Button(role: .destructive, action: leaveRelationship) {
                Text(.pairingUnpairConfirmAction)
            }
            .accessibilityIdentifier("settings.account.leave.confirm")
            Button(role: .cancel, action: {}) {
                Text(.pairingUnpairConfirmCancel)
            }
        } message: {
            Text(.pairingUnpairConfirmMessage(partnerName))
        }
    }

    private var deleteRow: some View {
        SettingsActionRow(
            title: .authDeleteAccountButton,
            systemImage: "trash",
            role: .destructive
        ) {
            isConfirmingDelete = true
        }
        .disabled(viewModel.isLeavingRelationship || isLoggingOut)
        .accessibilityIdentifier("settings.account.delete")
        .alert(Text(.authDeleteAccountConfirmTitle), isPresented: $isConfirmingDelete) {
            Button(role: .destructive, action: onDeleteAccount) {
                Text(.authDeleteAccountConfirmAction)
            }
            .accessibilityIdentifier("settings.account.delete.confirm")
            Button(role: .cancel, action: {}) {
                Text(.authDeleteAccountConfirmCancel)
            }
        } message: {
            Text(.authDeleteAccountConfirmMessage)
        }
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
