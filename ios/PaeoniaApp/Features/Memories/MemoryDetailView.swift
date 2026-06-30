import PhotosUI
import SwiftUI

/// A single memory, in full. Photos, both partners' notes, and the actions that change
/// it (edit your note, edit the title/date, add or remove photos, delete). The record
/// is re-read from the view model by id so the screen always reflects the latest local
/// state and dismisses itself once the memory is deleted.
struct MemoryDetailView: View {
    let memoryID: UUID
    let currentUserID: UUID?
    let viewModel: MemoriesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var isEditingNote = false
    @State private var isEditingDetails = false
    @State private var isAddingPhotos = false
    @State private var addPhotoItems: [PhotosPickerItem] = []
    @State private var photoToRemove: MemoryMediaSnapshot?
    @State private var isConfirmingDelete = false

    private let maxPhotosPerPartner = 5

    private var record: MemoryRecord? {
        viewModel.record(for: memoryID)
    }

    var body: some View {
        Group {
            if let record {
                content(for: record)
            } else {
                // The memory was deleted (or never loaded); fall back to a blank surface
                // while the dismiss below takes effect.
                Color.paeoniaBackgroundPrimary
            }
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(record?.snapshot.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .onChange(of: record == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .sheet(isPresented: $isEditingNote) { noteEditorSheet }
        .sheet(isPresented: $isEditingDetails) { detailsEditorSheet }
        .photosPicker(
            isPresented: $isAddingPhotos,
            selection: $addPhotoItems,
            maxSelectionCount: max(1, remainingPhotoSlots),
            matching: .images
        )
        .onChange(of: addPhotoItems) { _, items in
            loadAndAddPhotos(items)
        }
        .alert(
            Text(.memoriesDeleteTitle),
            isPresented: $isConfirmingDelete
        ) {
            Button(role: .cancel) {} label: { Text(.commonCancel) }
            Button(role: .destructive) {
                Task { await deleteMemory() }
            } label: {
                Text(.memoriesDeleteAction)
            }
        } message: {
            Text(.memoriesDeleteMessage)
        }
        .alert(
            Text(.memoriesPhotoRemoveTitle),
            isPresented: removePhotoAlertBinding
        ) {
            Button(role: .cancel) { photoToRemove = nil } label: { Text(.commonCancel) }
            Button(role: .destructive) {
                Task { await removePhoto() }
            } label: {
                Text(.memoriesPhotoRemoveAction)
            }
        }
    }

    private func content(for record: MemoryRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                header(for: record)

                if !visibleMedia(for: record).isEmpty {
                    photoGallery(for: record)
                }

                yourNoteSection(for: record)

                if let partnerNote = record.snapshot.partnerNote,
                   partnerNote.isVisible,
                   let body = partnerNote.body,
                   !body.isEmpty {
                    noteBlock(title: .memoriesDetailPartnerNote, body: body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
        }
    }

    private func header(for record: MemoryRecord) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(dayStartUTC(for: record), format: MemoryDateStyle.long)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaMemory)

            Text(record.snapshot.title ?? "")
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func photoGallery(for record: MemoryRecord) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            ForEach(visibleMedia(for: record), id: \.memoryMediaID) { media in
                ZStack(alignment: .topTrailing) {
                    MemoryMediaImageView(
                        mediaAssetID: media.mediaAssetID,
                        height: 280,
                        cornerRadius: PaeoniaRadius.radius16
                    )

                    // Only the photo's owner can remove it; the control is visible so it's
                    // discoverable, and removal is confirmed before it leaves for good.
                    if media.ownerUserID == currentUserID {
                        Button(role: .destructive) {
                            photoToRemove = media
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .accessibilityHidden(true)
                        }
                        .padding(PaeoniaSpacing.space8)
                        .accessibilityLabel(Text(.memoriesPhotoRemove))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func yourNoteSection(for record: MemoryRecord) -> some View {
        if let own = record.snapshot.ownNote, own.isVisible, let body = own.body, !body.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(.memoriesDetailYourNote)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextSecondary)

                    Spacer()

                    Button {
                        isEditingNote = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(PaeoniaTypography.body.weight(.semibold))
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .padding(PaeoniaSpacing.space4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(.memoriesDetailEditNote))
                }

                Text(body)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Button {
                isEditingNote = true
            } label: {
                Label {
                    Text(.memoriesDetailAddNote)
                } icon: {
                    Image(systemName: "square.and.pencil").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
    }

    private func noteBlock(title: LocalizedStringResource, body: String) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            Text(body)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if viewModel.canAttachPhotos, remainingPhotoSlots > 0 {
                    Button {
                        isAddingPhotos = true
                    } label: {
                        Label { Text(.memoriesDetailAddPhotos) } icon: { Image(systemName: "photo.badge.plus") }
                    }
                }

                Button {
                    isEditingDetails = true
                } label: {
                    Label { Text(.memoriesDetailEditDetails) } icon: { Image(systemName: "pencil") }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label { Text(.memoriesDetailDelete) } icon: { Image(systemName: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel(Text(.memoriesDetailMenu))
            }
        }
    }

    @ViewBuilder
    private var noteEditorSheet: some View {
        if let record {
            MemoryNoteEditorView(
                initialBody: record.snapshot.ownNote?.body ?? ""
            ) { body in
                await viewModel.saveNote(for: record, body: body)
            }
        }
    }

    @ViewBuilder
    private var detailsEditorSheet: some View {
        if let record {
            MemoryDetailsEditorView(
                initialTitle: record.snapshot.title ?? "",
                initialDate: MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
            ) { title, date in
                await viewModel.updateDetails(for: record, title: title, date: date)
            }
        }
    }

    // MARK: - Derived

    private var removePhotoAlertBinding: Binding<Bool> {
        Binding(
            get: { photoToRemove != nil },
            set: { if !$0 { photoToRemove = nil } }
        )
    }

    private func visibleMedia(for record: MemoryRecord) -> [MemoryMediaSnapshot] {
        record.snapshot.media.filter(\.isVisible).sortedForMemoryDisplay()
    }

    private func dayStartUTC(for record: MemoryRecord) -> Date {
        MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
    }

    /// How many more photos the current user may add (the backend caps each partner at
    /// five). Counts only the user's own visible photos.
    private var remainingPhotoSlots: Int {
        guard let record else { return 0 }
        let ownCount = record.snapshot.media
            .filter { $0.isVisible && $0.ownerUserID == currentUserID }
            .count
        return max(0, maxPhotosPerPartner - ownCount)
    }

    // MARK: - Actions

    private func deleteMemory() async {
        guard let record else { return }
        await viewModel.deleteMemory(record)
    }

    private func removePhoto() async {
        guard let record, let media = photoToRemove else { return }
        photoToRemove = nil
        await viewModel.removePhoto(from: record, media: media)
    }

    private func loadAndAddPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, let record else { return }
        Task {
            var loaded: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append(data)
                }
            }
            addPhotoItems = []
            guard !loaded.isEmpty else { return }
            _ = await viewModel.addPhotos(to: record, photos: loaded)
        }
    }
}

/// A focused sheet for writing the current user's note on a memory.
private struct MemoryNoteEditorView: View {
    let initialBody: String
    let onSave: (_ body: String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool?

    init(initialBody: String, onSave: @escaping (_ body: String) async -> Bool) {
        self.initialBody = initialBody
        self.onSave = onSave
        _text = State(initialValue: initialBody)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                MemoryTextField(
                    text: $text,
                    placeholder: .memoriesEditorNotePlaceholder,
                    isFocused: $isFocused,
                    field: true,
                    lineLimit: 4...12
                )
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
            }
            .background(.paeoniaBackgroundPrimary)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissable()
            .navigationTitle(Text(.memoriesNoteTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() } label: { Text(.commonCancel) }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(.memoriesNoteSave)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.paeoniaBackgroundPrimary)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        if await onSave(text) {
            dismiss()
        }
    }
}

/// A focused sheet for editing a memory's title and date.
private struct MemoryDetailsEditorView: View {
    let initialTitle: String
    let initialDate: Date
    let onSave: (_ title: String, _ date: String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var isSaving = false
    @FocusState private var isFocused: Bool?

    init(initialTitle: String, initialDate: Date, onSave: @escaping (_ title: String, _ date: String) async -> Bool) {
        self.initialTitle = initialTitle
        self.initialDate = initialDate
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    titleField
                    dateField
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
            }
            .background(.paeoniaBackgroundPrimary)
            .keyboardDismissable()
            .navigationTitle(Text(.memoriesEditDetailsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() } label: { Text(.commonCancel) }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(.memoriesEditDetailsSave)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.paeoniaBackgroundPrimary)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.memoriesEditorTitleLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
            MemoryTextField(
                text: $title,
                placeholder: .memoriesEditorTitlePlaceholder,
                isFocused: $isFocused,
                field: true,
                lineLimit: 1...2
            )
        }
    }

    private var dateField: some View {
        HStack {
            Text(.memoriesEditorDateLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
            Spacer(minLength: PaeoniaSpacing.space16)
            DatePicker(selection: $date, displayedComponents: [.date]) {
                Text(.memoriesEditorDateLabel)
            }
            .labelsHidden()
            .tint(.paeoniaAccentPrimary)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        if await onSave(title, MemoryTimeline.currentLocalDateString(now: date)) {
            dismiss()
        }
    }
}
