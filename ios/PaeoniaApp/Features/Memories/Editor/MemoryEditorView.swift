import SwiftUI
import UIKit

/// The memory form, for a new memory or an edit. Title and date are required. A new
/// memory also needs a note or at least one photo, so it always carries something to
/// remember. Photos are uploaded only when the memory is saved; the form just stages
/// picked images until then.
///
/// A new memory should take as few taps as possible: the title is focused when the form
/// opens, Return moves on to the note, the date starts at today, and Save sits in the
/// top bar so the keyboard never covers it.
///
/// A new memory's contents live in a `MemoryDraft` owned by the view model, so the
/// form survives an accidental swipe-down. An edit can't be swiped away while it has
/// changes; Cancel asks before throwing them away.
struct MemoryEditorView: View {
    enum Mode: Equatable {
        case create
        case edit

        var title: LocalizedStringResource {
            switch self {
            case .create:
                .memoriesEditorNewTitle
            case .edit:
                .memoriesEditorEditTitle
            }
        }
    }

    @Binding var draft: MemoryDraft
    var mode: Mode = .create
    var existingMedia: [MemoryMediaSnapshot] = []
    var currentUserID: UUID?
    /// Whether the person already has a note on this memory. Notes can be changed but
    /// not removed, so the form explains that instead of quietly keeping the old note.
    var hasExistingNote = false
    /// True when the memory being edited no longer exists (the partner deleted it). The
    /// form stays open so the typed text isn't lost, explains why it can't be saved,
    /// and offers to copy the text.
    var isMemoryRemoved = false
    /// Whether photo attachment is available (false in previews/tests without an
    /// uploader, or before the active couple is known). When false the photo controls
    /// are hidden and a note is required.
    let allowsPhotos: Bool
    /// Which photo is being sent while the memory saves, shown on the save button.
    var uploadProgress: MemoryPhotoUploadProgress?
    /// Places on the couple's other memories, for the place sheet.
    var knownPlaces: [MemoryPlace] = []
    /// Saves the memory. Returns whether it succeeded so the form can dismiss on success
    /// and stay put (with a banner already shown) on failure.
    let onSave: (
        _ title: String,
        _ date: String,
        _ note: String,
        _ photos: [Data],
        _ removedMedia: [MemoryMediaSnapshot],
        _ place: MemoryPlace?
    ) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    @State private var loadingPhotoCount = 0
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @State private var removedExistingMediaIDs: Set<UUID> = []
    /// The edit form as it opened, to tell whether anything changed.
    @State private var initialDraft: MemoryDraft?
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case note
    }

    var body: some View {
        NavigationStack {
            form
                .paeoniaScreenBackground()
                .scrollDismissesKeyboard(.interactively)
                .keyboardDismissable()
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { cancel() } label: {
                            Text(.commonCancel)
                        }
                        .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        saveButton
                    }
                }
                .alert(Text(.memoriesEditorDiscardTitle), isPresented: $isConfirmingDiscard) {
                    Button(role: .cancel) {} label: { Text(.memoriesEditorDiscardKeepEditing) }
                    Button(role: .destructive) { dismiss() } label: { Text(.memoriesEditorDiscardAction) }
                } message: {
                    Text(.memoriesEditorDiscardMessage)
                }
        }
        // The sheet covers the app's top banner, so show it here too. Otherwise a
        // failed save would look like nothing happened.
        .paeoniaTopBanner(bannerCenter)
        .presentationBackground(.paeoniaBackgroundPrimary)
        // A new memory's draft is kept on the device, so swiping it away is safe. An
        // edit isn't kept, and nothing may close the form while it saves.
        .interactiveDismissDisabled(isSaving || hasUnsavedEdits)
        .onAppear {
            switch mode {
            case .create:
                if draft.title.isEmpty {
                    focusedField = .title
                } else if draft.note.isEmpty {
                    focusedField = .note
                }
            case .edit:
                if initialDraft == nil {
                    initialDraft = draft
                }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                if isMemoryRemoved {
                    MemoryRemovedNotice(copyableText: draft.copyableText)
                }
                // Photos come first so the keyboard, which opens on the title, never
                // covers them.
                if allowsPhotos || !existingMedia.isEmpty {
                    MemoryEditorPhotosField(
                        photos: $draft.photos,
                        removedExistingMediaIDs: $removedExistingMediaIDs,
                        loadingPhotoCount: $loadingPhotoCount,
                        existingMedia: existingMedia,
                        currentUserID: currentUserID,
                        allowsPhotos: allowsPhotos,
                        isSaving: isSaving
                    )
                }
                titleField
                noteField
                dateField
                MemoryPlaceField(place: $draft.place, photos: draft.photos, knownPlaces: knownPlaces)
                    .disabled(isSaving)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space24)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Fields

    private var titleField: some View {
        MemoryTextField(
            text: $draft.title,
            placeholder: .memoriesEditorTitlePlaceholder,
            isFocused: $focusedField,
            field: .title,
            axis: .horizontal,
            characterLimit: MemoryDataService.titleCharacterLimit
        )
        .submitLabel(.next)
        .onSubmit { focusedField = .note }
    }

    private var dateField: some View {
        HStack {
            Text(.memoriesEditorDateLabel)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
            Spacer(minLength: PaeoniaSpacing.space16)
            // A memory is something that already happened, so the latest choice is today.
            // The bound is the end of today: an edit's date sits at noon, which can still
            // be ahead of the clock in the morning.
            DatePicker(
                selection: $draft.date,
                in: ...endOfToday,
                displayedComponents: [.date]
            ) {
                Text(.memoriesEditorDateLabel)
            }
            .labelsHidden()
            .tint(.paeoniaAccentPrimary)
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            MemoryTextField(
                text: $draft.note,
                placeholder: .memoriesEditorNotePlaceholder,
                isFocused: $focusedField,
                field: .note,
                lineLimit: 3...8,
                characterLimit: MemoryDataService.noteCharacterLimit
            )

            if isClearingExistingNote {
                Text(.memoriesEditorNoteRequired)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: isClearingExistingNote)
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                ProgressView()
            } else {
                Text(.memoriesEditorSave)
            }
        }
        .disabled(!canSave || isSaving)
    }

    /// While photos send, the title counts them, since saving can take a while.
    private var navigationTitle: Text {
        if isSaving, let uploadProgress {
            Text(.memoriesEditorUploadingPhoto(
                uploadProgress.current.formatted(),
                uploadProgress.total.formatted()
            ))
        } else {
            Text(mode.title)
        }
    }

    // MARK: - State

    /// The person emptied a note they already have. The server can't remove a note, so
    /// saving would quietly keep the old one.
    private var isClearingExistingNote: Bool {
        mode == .edit && hasExistingNote && draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        guard !isMemoryRemoved, loadingPhotoCount == 0 else { return false }
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch mode {
        case .create:
            return !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.photos.isEmpty
        case .edit:
            return !isClearingExistingNote
        }
    }

    private var hasUnsavedEdits: Bool {
        guard mode == .edit, !isMemoryRemoved, let initialDraft else { return false }
        return draft.title != initialDraft.title
            || draft.note != initialDraft.note
            || draft.place != initialDraft.place
            || !draft.photos.isEmpty
            || !removedExistingMediaIDs.isEmpty
            || MemoryTimeline.localDateString(for: draft.date) != MemoryTimeline.localDateString(for: initialDraft.date)
    }

    private var endOfToday: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
    }

    // MARK: - Actions

    /// Cancel on a new memory is a deliberate discard, so it clears the draft. Cancel on
    /// an edit with changes asks first.
    private func cancel() {
        switch mode {
        case .create:
            draft = MemoryDraft()
            dismiss()
        case .edit:
            if hasUnsavedEdits {
                isConfirmingDiscard = true
            } else {
                dismiss()
            }
        }
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }

        let saved = await onSave(
            draft.title,
            MemoryTimeline.localDateString(for: draft.date),
            draft.note,
            draft.photos.map(\.data),
            existingMedia.filter { removedExistingMediaIDs.contains($0.memoryMediaID) },
            draft.place
        )
        if saved {
            dismiss()
        }
    }
}

/// Shown in the edit form when the partner deleted the memory. Explains why it can't be
/// saved and offers to copy the typed text first.
private struct MemoryRemovedNotice: View {
    let copyableText: String

    @State private var didCopyText = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.memoriesEditorRemovedTitle)
                .font(PaeoniaTypography.body.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
            Text(.memoriesEditorRemovedMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            if !copyableText.isEmpty {
                Button {
                    UIPasteboard.general.string = copyableText
                    didCopyText = true
                } label: {
                    Label {
                        Text(didCopyText ? .memoriesEditorRemovedCopied : .memoriesEditorRemovedCopy)
                    } icon: {
                        Image(systemName: didCopyText ? "checkmark" : "doc.on.doc").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
            }
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
