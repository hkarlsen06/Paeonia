import SwiftUI

/// The screen behind the More tab's profile row: the user's name and photo, and the
/// account actions below them.
///
/// While there are unsaved edits the back button steps aside for Cancel, so a
/// stray swipe can never throw away a new name or photo. Save sits under the name
/// field, since it saves only the name and photo. The More tab shows the banner
/// for the result, so it still appears if the user has moved on.
struct ProfileSettingsView: View {
    let editor: ProfileEditorViewModel
    let savedDisplayName: String?
    let customProfilePhotoAssetID: UUID?
    let providerProfilePhotoAssetID: UUID?
    let onSave: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool
    /// Nil when the build has no sign-in service, so the section is hidden.
    let signInMethods: SignInMethodsViewModel?
    let accountSection: SettingsAccountSection

    var body: some View {
        Form {
            Section {
                ProfileHeaderEditorView(editor: editor, onSave: onSave)
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .listRowBackground(Color.clear)
            }

            if let signInMethods {
                SettingsSignInMethodsSection(viewModel: signInMethods)
                    .listRowBackground(Color.paeoniaSurfacePrimary)
            }

            accountSection
                .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsProfileSectionTitle))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(holdsUnsavedEdits)
        .toolbar {
            if holdsUnsavedEdits {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        PaeoniaKeyboard.dismiss()
                        editor.discard()
                    } label: {
                        Text(.commonCancel)
                    }
                    .accessibilityIdentifier("settings.profile.cancel")
                }
            }
        }
        .task {
            await signInMethods?.refresh()
        }
        // The name field lives on this screen, so the keyboard needs the standard
        // Done button and scroll-away dismissal here. Not tap-away: a tap gesture
        // on a Form swallows the taps on its button rows, so the account rows
        // below would never open their confirmations.
        .keyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: savedProfile, initial: true) { _, saved in
            editor.updateSavedProfile(
                name: saved.name,
                customPhotoAssetID: saved.customPhotoAssetID,
                providerPhotoAssetID: saved.providerPhotoAssetID
            )
        }
    }

    /// Edits or a photo still loading keep the user here until they save or
    /// cancel. A running save does not: it finishes on its own and the More tab
    /// shows how it went.
    private var holdsUnsavedEdits: Bool {
        (editor.draft.hasChanges || editor.isLoadingPhoto) && !editor.isSaving
    }

    /// The saved profile can change while the screen is open, for example when
    /// the name finishes loading or another device changes the photo.
    private var savedProfile: SavedProfile {
        SavedProfile(
            name: savedDisplayName,
            customPhotoAssetID: customProfilePhotoAssetID,
            providerPhotoAssetID: providerProfilePhotoAssetID
        )
    }
}

private struct SavedProfile: Equatable {
    let name: String?
    let customPhotoAssetID: UUID?
    let providerPhotoAssetID: UUID?
}

#Preview {
    NavigationStack {
        ProfileSettingsView(
            editor: ProfileEditorViewModel(),
            savedDisplayName: "Hjalmar",
            customProfilePhotoAssetID: nil,
            providerProfilePhotoAssetID: nil,
            onSave: { _, _ in true },
            signInMethods: nil,
            accountSection: SettingsAccountSection(
                viewModel: SettingsViewModel(),
                partnerName: "Oda",
                ownAccess: .appStoreSubscription,
                onLeftRelationship: {},
                onLogout: {},
                onDeleteAccount: {}
            )
        )
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
