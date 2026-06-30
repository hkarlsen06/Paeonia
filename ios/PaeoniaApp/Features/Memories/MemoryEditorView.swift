import PhotosUI
import SwiftUI
import UIKit

/// The focused form for creating a new memory. Title and date are required, plus at
/// least a note or one photo, so a saved memory always carries something to remember.
/// Photos are uploaded only when the memory is saved; the form just stages picked
/// images until then.
struct MemoryEditorView: View {
    /// Whether photo attachment is available (false in previews/tests without an
    /// uploader, or before the active couple is known). When false the photo controls
    /// are hidden and a note is required.
    let allowsPhotos: Bool
    /// Saves the memory. Returns whether it succeeded so the form can dismiss on success
    /// and stay put (with a banner already shown) on failure.
    let onSave: (_ title: String, _ date: String, _ note: String, _ photos: [Data]) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var photos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isSaving = false
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

                    if allowsPhotos {
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
            .navigationTitle(Text(.memoriesEditorNewTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() } label: {
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
        }
        .presentationBackground(.paeoniaBackgroundPrimary)
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            fieldLabel(.memoriesEditorTitleLabel)

            MemoryTextField(
                text: $title,
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
                selection: $date,
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
                text: $note,
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

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PaeoniaSpacing.space8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            stagedThumbnail(data, index: index)
                        }
                    }
                }
            }

            if photos.count < maxPhotos {
                photoPickerControls
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

            Button(role: .destructive) {
                photos.remove(at: index)
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
                maxSelectionCount: maxPhotos - photos.count,
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
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasContent
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let saved = await onSave(title, dateString, note, photos)
        if saved {
            dismiss()
        }
    }

    /// The chosen date as a `yyyy-MM-dd` string in the device's local calendar, matching
    /// how the day is displayed in the picker.
    private var dateString: String {
        MemoryTimeline.currentLocalDateString(now: date)
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
            let room = max(0, maxPhotos - photos.count)
            photos.append(contentsOf: loaded.prefix(room))
            pickerItems = []
        }
    }

    private func appendPhoto(_ data: Data) {
        guard photos.count < maxPhotos else { return }
        photos.append(data)
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
