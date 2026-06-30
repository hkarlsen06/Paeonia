import PhotosUI
import SwiftUI
import UIKit

/// The in-progress contents of the new-memory form. Held by the presenting screen, not
/// by the sheet, so dismissing the sheet — including an accidental swipe-down while
/// reaching for the keyboard — keeps the work. Reopening restores it; a successful save
/// (or a deliberate Cancel) resets it.
struct MemoryDraft: Equatable {
    var title: String = ""
    var date: Date = Date()
    var note: String = ""
    var photos: [Data] = []

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photos.isEmpty
    }
}

/// The focused form for creating a new memory. Title and date are required, plus at
/// least a note or one photo, so a saved memory always carries something to remember.
/// Photos are uploaded only when the memory is saved; the form just stages picked
/// images until then. The editable contents live in a `MemoryDraft` binding owned by the
/// presenting screen so the form survives an accidental dismissal.
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
    /// Whether photo attachment is available (false in previews/tests without an
    /// uploader, or before the active couple is known). When false the photo controls
    /// are hidden and a note is required.
    let allowsPhotos: Bool
    /// Saves the memory. Returns whether it succeeded so the form can dismiss on success
    /// and stay put (with a banner already shown) on failure.
    let onSave: (
        _ title: String,
        _ date: String,
        _ note: String,
        _ photos: [Data],
        _ removedMedia: [MemoryMediaSnapshot]
    ) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isSaving = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?
    @State private var removedExistingMediaIDs: Set<UUID> = []
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case note
    }

    private let maxPhotos = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    titleField
                    dateField
                    noteField

                    if allowsPhotos || !existingMedia.isEmpty {
                        photosSection
                    }
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space24)
            }
            .background(.paeoniaBackgroundPrimary)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissable()
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle(Text(mode.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { cancel() } label: {
                        Text(.commonCancel)
                    }
                    .disabled(isSaving)
                }
            }
            .onChange(of: pickerItems) { _, items in
                loadPickedPhotos(items)
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                DailyCameraPicker(onCapture: appendPhoto)
                    .ignoresSafeArea()
            }
            .paeoniaImageViewer(selection: $imageViewerSelection)
        }
        .presentationBackground(.paeoniaBackgroundPrimary)
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            fieldLabel(.memoriesEditorTitleLabel)

            MemoryTextField(
                text: $draft.title,
                placeholder: .memoriesEditorTitlePlaceholder,
                isFocused: $focusedField,
                field: .title,
                lineLimit: 1...2
            )
        }
    }

    private var dateField: some View {
        HStack {
            fieldLabel(.memoriesEditorDateLabel)
            Spacer(minLength: PaeoniaSpacing.space16)
            DatePicker(
                selection: $draft.date,
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
            fieldLabel(.memoriesEditorNoteLabel)

            MemoryTextField(
                text: $draft.note,
                placeholder: .memoriesEditorNotePlaceholder,
                isFocused: $focusedField,
                field: .note,
                lineLimit: 3...8
            )
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            fieldLabel(.memoriesEditorPhotosLabel)

            if !visibleExistingMedia.isEmpty || !draft.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PaeoniaSpacing.space8) {
                        ForEach(visibleExistingMedia, id: \.memoryMediaID) { media in
                            existingThumbnail(media)
                        }
                        ForEach(Array(draft.photos.enumerated()), id: \.offset) { index, data in
                            stagedThumbnail(data, index: index)
                        }
                    }
                }
            }

            if canAddPhotos {
                photoPickerControls
            }
        }
    }

    private func existingThumbnail(_ media: MemoryMediaSnapshot) -> some View {
        ZStack(alignment: .topTrailing) {
            MemoryMediaImageView(
                mediaAssetID: media.mediaAssetID,
                height: 104,
                cornerRadius: PaeoniaRadius.radius12
            )
            .frame(width: 104)

            if media.ownerUserID == currentUserID {
                Button(role: .destructive) {
                    removedExistingMediaIDs.insert(media.memoryMediaID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .accessibilityHidden(true)
                }
                .padding(PaeoniaSpacing.space4)
                .accessibilityLabel(Text(.memoriesPhotoRemove))
            }
        }
    }

    private func stagedThumbnail(_ data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.paeoniaSurfaceSecondary
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .onTapGesture {
                presentStagedImage(data)
            }
            .accessibilityLabel(Text(.memoriesPhotoAccessibility))
            .accessibilityAddTraits(.isButton)

            Button(role: .destructive) {
                draft.photos.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(PaeoniaSpacing.space4)
            .accessibilityLabel(Text(.memoriesPhotoRemove))
        }
    }

    private var photoPickerControls: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: maxPhotos - ownVisiblePhotoCount - draft.photos.count,
                matching: .images
            ) {
                Label {
                    Text(.memoriesEditorAddPhoto)
                } icon: {
                    Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)

            if DailyCameraPicker.isAvailable {
                Button {
                    isCameraPresented = true
                } label: {
                    Label {
                        Text(.memoriesEditorTakePhoto)
                    } icon: {
                        Image(systemName: "camera").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                ProgressView().tint(.paeoniaTextInverse)
            } else {
                Text(.memoriesEditorSave)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canSave || isSaving)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(.paeoniaBackgroundPrimary)
    }

    private func fieldLabel(_ key: LocalizedStringResource) -> some View {
        Text(key)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextSecondary)
    }

    // MARK: - Actions

    private var hasContent: Bool {
        !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.photos.isEmpty
            || !visibleExistingMedia.isEmpty
    }

    private var canSave: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch mode {
        case .create:
            return hasContent
        case .edit:
            return true
        }
    }

    private var visibleExistingMedia: [MemoryMediaSnapshot] {
        existingMedia.filter { !removedExistingMediaIDs.contains($0.memoryMediaID) }
    }

    private var removedExistingMedia: [MemoryMediaSnapshot] {
        existingMedia.filter { removedExistingMediaIDs.contains($0.memoryMediaID) }
    }

    private var ownVisiblePhotoCount: Int {
        visibleExistingMedia.filter { $0.ownerUserID == currentUserID }.count
    }

    private var canAddPhotos: Bool {
        allowsPhotos && ownVisiblePhotoCount + draft.photos.count < maxPhotos
    }

    /// Deliberate abandon for new memories clears the draft so reopening starts fresh.
    /// Edit mode leaves the caller-owned draft alone; it gets reset when the sheet opens.
    private func cancel() {
        if mode == .create {
            draft = MemoryDraft()
        }
        dismiss()
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let saved = await onSave(draft.title, dateString, draft.note, draft.photos, removedExistingMedia)
        if saved {
            dismiss()
        }
    }

    /// The chosen date as a `yyyy-MM-dd` string in the device's local calendar, matching
    /// how the day is displayed in the picker.
    private var dateString: String {
        MemoryTimeline.currentLocalDateString(now: draft.date)
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loaded: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append(data)
                }
            }
            let room = max(0, maxPhotos - ownVisiblePhotoCount - draft.photos.count)
            draft.photos.append(contentsOf: loaded.prefix(room))
            pickerItems = []
        }
    }

    private func appendPhoto(_ data: Data) {
        guard canAddPhotos else { return }
        draft.photos.append(data)
    }

    private func presentStagedImage(_ data: Data) {
        guard let uiImage = UIImage(data: data) else { return }
        imageViewerSelection = PaeoniaImageViewerSelection(image: uiImage)
    }
}

/// A styled multiline text field matching the daily composer: surface background, a
/// hairline border that brightens on focus, and Dynamic Type-friendly body text.
struct MemoryTextField<Field: Hashable>: View {
    @Binding var text: String
    let placeholder: LocalizedStringResource
    var isFocused: FocusState<Field?>.Binding
    let field: Field
    var lineLimit: ClosedRange<Int> = 1...4

    private var isActive: Bool {
        isFocused.wrappedValue == field
    }

    var body: some View {
        TextField(
            text: $text,
            prompt: Text(placeholder),
            axis: .vertical
        ) {
            Text(placeholder)
        }
        .lineLimit(lineLimit)
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(PaeoniaSpacing.space12)
        .focused(isFocused, equals: field)
        .background(.paeoniaBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                .stroke(
                    isActive ? Color.paeoniaAccentPrimary : Color.paeoniaSurfacePressed,
                    lineWidth: isActive ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                )
        }
        .animation(PaeoniaMotion.stateChange, value: isActive)
    }
}
