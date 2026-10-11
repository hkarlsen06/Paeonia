import SwiftUI
import UIKit

/// A single memory, in full. Photos, both partners' notes, and the actions that change
/// it through the edit sheet or delete confirmation. The record is re-read from the
/// view model by id so the screen always reflects the latest local state and dismisses
/// itself once the memory is deleted.
struct MemoryDetailView: View {
    let memoryID: UUID
    let currentUserID: UUID?
    let viewModel: MemoriesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var isEditingMemory = false
    @State private var editDraft = MemoryDraft()
    /// The memory as it was when the edit sheet opened. Saving compares against it, so
    /// only what the person changed is sent, and the sheet keeps using it if the
    /// memory is deleted mid-edit so the typed text stays on screen.
    @State private var editingRecord: MemoryRecord?
    @State private var wasRemovedWhileEditing = false
    @State private var isConfirmingDelete = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    private let photoCarouselHeight: CGFloat = 320
    private let photoCarouselPageControlInset: CGFloat = PaeoniaSpacing.space40

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
            guard isGone else { return }
            // Closing the screen now would also close the edit sheet and drop the
            // unsaved text. Keep the sheet open and explain instead.
            if isEditingMemory {
                wasRemovedWhileEditing = true
            } else {
                dismiss()
            }
        }
        .sheet(isPresented: $isEditingMemory, onDismiss: closeAfterRemoval) { memoryEditorSheet }
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
        .paeoniaImageViewer(selection: $imageViewerSelection)
    }

    private func content(for record: MemoryRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                header(for: record)

                if !visibleMedia(for: record).isEmpty {
                    photoGallery(for: record)
                }

                yourNoteSection(for: record)

                if let body = visibleBody(of: record.snapshot.partnerNote) {
                    noteBlock(title: .memoriesDetailPartnerNote, body: body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth()
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
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .combine)
    }

    private func photoGallery(for record: MemoryRecord) -> some View {
        let mediaItems = visibleMedia(for: record)
        return TabView {
            ForEach(mediaItems, id: \.memoryMediaID) { media in
                MemoryMediaImageView(
                    mediaAssetID: media.mediaAssetID,
                    height: photoCarouselHeight,
                    cornerRadius: PaeoniaRadius.radius16,
                    onTapImage: { mediaAssetID, _ in
                        presentImageViewer(initialMediaAssetID: mediaAssetID, mediaItems: mediaItems)
                    }
                )
                .contextMenu {
                    savePhotoButton(for: media)
                }
                .accessibilityAction(named: Text(.memoriesPhotoSave)) {
                    Task { await viewModel.savePhotoToLibrary(mediaAssetID: media.mediaAssetID) }
                }
                .padding(.bottom, mediaItems.count > 1 ? photoCarouselPageControlInset : 0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: mediaItems.count > 1 ? .automatic : .never))
        .frame(height: mediaItems.count > 1 ? photoCarouselHeight + photoCarouselPageControlInset : photoCarouselHeight)
    }

    private func savePhotoButton(for media: MemoryMediaSnapshot) -> some View {
        Button {
            Task { await viewModel.savePhotoToLibrary(mediaAssetID: media.mediaAssetID) }
        } label: {
            Label { Text(.memoriesPhotoSave) } icon: { Image(systemName: "square.and.arrow.down") }
        }
    }

    /// The person's own note, or a quiet prompt to add one when they haven't yet.
    @ViewBuilder
    private func yourNoteSection(for record: MemoryRecord) -> some View {
        if let body = visibleBody(of: record.snapshot.ownNote) {
            noteBlock(title: .memoriesDetailYourNote, body: body)
        } else {
            Button {
                openMemoryEditor()
            } label: {
                Label {
                    Text(.memoriesDetailAddNote)
                } icon: {
                    Image(systemName: "square.and.pencil").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
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
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    openMemoryEditor()
                } label: {
                    Label { Text(.memoriesDetailEditMemory) } icon: { Image(systemName: "pencil") }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label { Text(.memoriesDetailDelete) } icon: { Image(systemName: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel(Text(.memoriesDetailMenu))
            }
            .disabled(record == nil)
        }
    }

    @ViewBuilder
    private var memoryEditorSheet: some View {
        if let base = editingRecord {
            let current = record ?? base
            MemoryEditorView(
                draft: $editDraft,
                mode: .edit,
                existingMedia: visibleMedia(for: current),
                currentUserID: currentUserID,
                hasExistingNote: visibleBody(of: current.snapshot.ownNote) != nil,
                isMemoryRemoved: wasRemovedWhileEditing,
                allowsPhotos: viewModel.canAttachPhotos,
                uploadProgress: viewModel.photoUploadProgress
            ) { title, date, note, photos, removedMedia in
                await viewModel.saveEdits(
                    MemoryEdit(
                        base: base,
                        title: title,
                        date: date,
                        note: note,
                        newPhotos: photos,
                        removedMedia: removedMedia
                    )
                )
            }
        }
    }

    // MARK: - Derived

    private func visibleMedia(for record: MemoryRecord) -> [MemoryMediaSnapshot] {
        record.snapshot.media.filter(\.isVisible).sortedForMemoryDisplay()
    }

    private func visibleBody(of note: MemoryNoteSnapshot?) -> String? {
        guard let note, note.isVisible, let body = note.body, !body.isEmpty else { return nil }
        return body
    }

    private func dayStartUTC(for record: MemoryRecord) -> Date {
        MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
    }

    // MARK: - Actions

    private func openMemoryEditor() {
        guard let record else { return }
        editDraft = MemoryDraft(
            title: record.snapshot.title ?? "",
            date: MemoryTimeline.pickerDate(forLocalDate: record.snapshot.memoryDate) ?? record.snapshot.createdAt,
            note: visibleBody(of: record.snapshot.ownNote) ?? "",
            photos: []
        )
        editingRecord = record
        wasRemovedWhileEditing = false
        isEditingMemory = true
    }

    /// After the sheet closes on a memory that was deleted, there is nothing left to
    /// show, so leave the detail screen.
    private func closeAfterRemoval() {
        editingRecord = nil
        if wasRemovedWhileEditing || record == nil {
            wasRemovedWhileEditing = false
            dismiss()
        }
    }

    private func deleteMemory() async {
        guard let record else { return }
        await viewModel.deleteMemory(record)
    }

    /// Opens the full-screen viewer on the tapped photo, with every photo of the memory
    /// to swipe through. Each page loads the full-resolution photo itself; the carousel
    /// only holds smaller copies.
    private func presentImageViewer(initialMediaAssetID: UUID?, mediaItems: [MemoryMediaSnapshot]) {
        guard let initialMediaAssetID else { return }
        let provider = MemoryMediaImageProviderFactory.shared
        let items = mediaItems.map { media in
            let mediaAssetID = media.mediaAssetID
            return PaeoniaImageViewerItem(id: mediaAssetID) {
                guard let data = await provider?.imageData(for: mediaAssetID) else { return nil }
                return UIImage(data: data)
            }
        }
        imageViewerSelection = PaeoniaImageViewerSelection(
            items: items,
            initialItemID: initialMediaAssetID.uuidString
        )
    }
}
