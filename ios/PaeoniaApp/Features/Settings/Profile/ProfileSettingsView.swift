import SwiftUI

/// The screen behind the Me tab's identity row: the inline name and photo editor,
/// with the account actions underneath it.
///
/// Signing out, leaving the relationship, and deleting the account all live here
/// rather than on the tab itself, so no destructive action sits one stray tap away
/// from the settings a user opens every day.
struct ProfileSettingsView: View {
    let viewModel: SettingsViewModel
    let savedDisplayName: String?
    let customProfilePhotoAssetID: UUID?
    let providerProfilePhotoAssetID: UUID?
    let authProvider: AuthProvider?
    /// Names the partner in the unpair confirmation instead of saying "your partner".
    let partnerName: String
    let onSave: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool
    let onLeftRelationship: () -> Void
    let onLogout: () -> Void
    let onDeleteAccount: () -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// Gates leaving behind a centered confirmation alert, so the pairing can never
    /// end on a single stray tap.
    @State private var isConfirmingLeave = false
    @State private var isConfirmingDelete = false

    var body: some View {
        SettingsDetailScreen(title: .settingsProfileSectionTitle) {
            ProfileHeaderEditorView(
                savedDisplayName: savedDisplayName,
                customProfilePhotoAssetID: customProfilePhotoAssetID,
                providerProfilePhotoAssetID: providerProfilePhotoAssetID,
                authProvider: authProvider,
                onSave: { [onSave] displayName, photoUpdate in
                    await onSave(displayName, photoUpdate)
                }
            )

            accountActions
        }
        // The name field lives on this screen, so the keyboard needs the standard
        // Done button and tap/scroll-away dismissal here.
        .keyboardDismissable()
        .scrollDismissesKeyboard(.interactively)
        .alert(
            Text(.pairingUnpairConfirmTitle(partnerName)),
            isPresented: $isConfirmingLeave
        ) {
            Button(role: .destructive, action: leaveRelationship) {
                Text(.pairingUnpairConfirmAction)
            }

            Button(role: .cancel, action: {}) {
                Text(.pairingUnpairConfirmCancel)
            }
        } message: {
            Text(.pairingUnpairConfirmMessage(partnerName))
        }
        .alert(
            Text(.authDeleteAccountConfirmTitle),
            isPresented: $isConfirmingDelete
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

    /// Log out and leave-relationship sit together as real buttons. Leaving is
    /// destructive, so it uses the destructive style and a broken-heart icon, and
    /// still only opens the confirmation alert — nothing happens until the user
    /// confirms there.
    private var accountActions: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.settingsAccountSectionTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)

            Button(action: onLogout) {
                Text(.settingsAccountLogoutButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())

            Button {
                isConfirmingLeave = true
            } label: {
                Label {
                    Text(.settingsUnpairButton)
                } icon: {
                    Image(systemName: "heart.slash.fill")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaDestructiveButtonStyle())
            .disabled(viewModel.isLeavingRelationship)

            // Delete stays quiet so it doesn't compete with the leave button above
            // it: leaving is the likelier intent, deleting is the last resort.
            Button {
                isConfirmingDelete = true
            } label: {
                Text(.authDeleteAccountButton)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PaeoniaQuietDestructiveButtonStyle())
            .disabled(viewModel.isLeavingRelationship)
        }
        .padding(.top, PaeoniaSpacing.space24)
    }

    private func leaveRelationship() {
        Task {
            let didLeave = await viewModel.leaveRelationship()
            if didLeave {
                bannerCenter.dismiss()
                onLeftRelationship()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSettingsView(
            viewModel: SettingsViewModel(),
            savedDisplayName: "Hjalmar",
            customProfilePhotoAssetID: nil,
            providerProfilePhotoAssetID: nil,
            authProvider: .apple,
            partnerName: "Oda",
            onSave: { _, _ in true },
            onLeftRelationship: {},
            onLogout: {},
            onDeleteAccount: {}
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
