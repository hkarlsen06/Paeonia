import SwiftUI

/// The screen behind the Us tab's nickname row: one field for what the person calls their partner.
///
/// While there are unsaved edits the back button steps aside for Cancel, like the profile screen, so a
/// stray swipe never throws away typed text. Save sits at the bottom within thumb reach. The Us tab
/// shows the banner for the result, so it still appears if the person has moved on.
struct PartnerNicknameView: View {
    let editor: PartnerNicknameEditorModel
    /// The partner's own name. The editor is the one screen that shows it next to the nickname.
    let partnerAccountName: String?
    let savedNickname: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            fieldSection
            if editor.hasSavedNickname {
                removeSection
            }
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsPartnerNicknameTitle))
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
        .keyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: savedNickname, initial: true) { _, nickname in
            editor.updateSavedNickname(nickname)
        }
    }

    private var partnerNameForCopy: String {
        partnerAccountName ?? String(localized: .pairingCelebrationPartnerName)
    }

    private var fieldSection: some View {
        Section {
            TextField(
                text: Binding(get: { editor.text }, set: editor.setText),
                prompt: Text(verbatim: partnerNameForCopy)
            ) {
                Text(.settingsPartnerNicknameFieldLabel)
            }
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { PaeoniaKeyboard.dismiss() }
            .disabled(editor.isSaving)
            .accessibilityIdentifier("settings.partnerNickname.field")
        } footer: {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                if editor.isTooLong {
                    Text(.settingsPartnerNicknameTooLong(PartnerName.maxNicknameLength))
                        .foregroundStyle(.paeoniaWarning)
                }
                Text(.settingsPartnerNicknameFooter(partnerNameForCopy))
            }
        }
        .listRowBackground(Color.paeoniaSurfacePrimary)
    }

    private var removeSection: some View {
        Section {
            Button {
                PaeoniaKeyboard.dismiss()
                Task { await editor.remove() }
            } label: {
                Label {
                    Text(.settingsPartnerNicknameRemove)
                        .foregroundStyle(.paeoniaTextPrimary)
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .disabled(editor.isSaving)
            .accessibilityIdentifier("settings.partnerNickname.remove")
        }
        .listRowBackground(Color.paeoniaSurfacePrimary)
    }

    private var holdsUnsavedEdits: Bool {
        editor.hasChanges && !editor.isSaving
    }

    private var showsSaveBar: Bool {
        editor.hasChanges || editor.isSaving
    }

    private var saveBar: some View {
        Button {
            PaeoniaKeyboard.dismiss()
            Task { await editor.save() }
        } label: {
            HStack(spacing: PaeoniaSpacing.space8) {
                if editor.isSaving {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                        .accessibilityHidden(true)
                }

                Text(editor.isSaving ? .settingsProfileSaving : .settingsPartnerNicknameSave)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!editor.canSave)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
        .accessibilityIdentifier("settings.partnerNickname.save")
    }
}

#Preview {
    NavigationStack {
        PartnerNicknameView(
            editor: PartnerNicknameEditorModel(gateway: nil),
            partnerAccountName: "Oda",
            savedNickname: "Oda 🌸"
        )
    }
    .preferredColorScheme(.dark)
}
