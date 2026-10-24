import SwiftUI

/// The screen behind the Us tab's profile row: the user's name and photo, and the
/// account actions below them.
///
/// While there are unsaved edits the back button steps aside for Cancel, so a
/// stray swipe can never throw away a new name or photo. Save sits at the bottom
/// within thumb reach, and the keyboard covers it while the name is typed. The Us tab shows the banner
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Section {
                ProfileHeaderEditorView(editor: editor)
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
        .paeoniaBottomBar {
            if showsSaveBar {
                saveBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: showsSaveBar)
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
    /// cancel. A running save does not: it finishes on its own and the Us tab
    /// shows how it went.
    private var holdsUnsavedEdits: Bool {
        (editor.draft.hasChanges || editor.isLoadingPhoto) && !editor.isSaving
    }

    private var showsSaveBar: Bool {
        editor.draft.hasChanges || editor.isSaving
    }

    private var saveBar: some View {
        Button {
            PaeoniaKeyboard.dismiss()
            Task { await editor.save(using: onSave) }
        } label: {
            HStack(spacing: PaeoniaSpacing.space8) {
                if editor.isSaving {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                }

                Text(editor.isSaving ? .settingsProfileSaving : .settingsProfileSave)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!editor.canSave)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
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
