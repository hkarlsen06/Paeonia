import SwiftUI
import UIKit

/// A single memory, in full. Photos, both partners' notes, and the actions that change
/// it through the edit sheet or delete confirmation. The record
/// is re-read from the view model by id so the screen always reflects the latest local
/// state and dismisses itself once the memory is deleted.
struct MemoryDetailView: View {
    let memoryID: UUID
    let currentUserID: UUID?
    let viewModel: MemoriesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var isEditingMemory = false
    @State private var editDraft = MemoryDraft()
    @State private var isConfirmingDelete = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?
    @State private var loadedImagesByMediaAssetID: [UUID: UIImage] = [:]

    private let photoCarouselHeight: CGFloat = 280
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
            if isGone { dismiss() }
        }
        .sheet(isPresented: $isEditingMemory) { memoryEditorSheet }
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
        let mediaItems = visibleMedia(for: record)
        return TabView {
            ForEach(mediaItems, id: \.memoryMediaID) { media in
                MemoryMediaImageView(
                    mediaAssetID: media.mediaAssetID,
                    height: photoCarouselHeight,
                    cornerRadius: PaeoniaRadius.radius16,
                    onTapImage: { mediaAssetID, image in
                        presentImageViewer(
                            initialMediaAssetID: mediaAssetID,
                            image: image,
                            record: record
                        )
                    },
                    onImageLoaded: { mediaAssetID, image in
                        loadedImagesByMediaAssetID[mediaAssetID] = image
                    }
                )
                .padding(.bottom, mediaItems.count > 1 ? photoCarouselPageControlInset : 0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: mediaItems.count > 1 ? .automatic : .never))
        .frame(height: mediaItems.count > 1 ? photoCarouselHeight + photoCarouselPageControlInset : photoCarouselHeight)
    }

    @ViewBuilder
    private func yourNoteSection(for record: MemoryRecord) -> some View {
        if let own = record.snapshot.ownNote, own.isVisible, let body = own.body, !body.isEmpty {
            noteBlock(title: .memoriesDetailYourNote, body: body)
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
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel(Text(.memoriesDetailMenu))
            }
        }
    }

    @ViewBuilder
    private var memoryEditorSheet: some View {
        if let record {
            MemoryEditorView(
                draft: $editDraft,
                mode: .edit,
                existingMedia: visibleMedia(for: record),
                currentUserID: currentUserID,
                allowsPhotos: viewModel.canAttachPhotos
            ) { title, date, note, photos, removedMedia in
                await saveMemoryEdits(
                    record: record,
                    title: title,
                    date: date,
                    note: note,
                    photos: photos,
                    removedMedia: removedMedia
                )
            }
        }
    }

    // MARK: - Derived

    private func visibleMedia(for record: MemoryRecord) -> [MemoryMediaSnapshot] {
        record.snapshot.media.filter(\.isVisible).sortedForMemoryDisplay()
    }

    private func dayStartUTC(for record: MemoryRecord) -> Date {
        MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
    }

    // MARK: - Actions

    private func openMemoryEditor() {
        guard let record else { return }
        editDraft = MemoryDraft(
            title: record.snapshot.title ?? "",
            date: dayStartUTC(for: record),
            note: record.snapshot.ownNote?.body ?? "",
            photos: []
        )
        isEditingMemory = true
    }

    private func deleteMemory() async {
        guard let record else { return }
        await viewModel.deleteMemory(record)
    }

    private func presentImageViewer(initialMediaAssetID: UUID?, image: UIImage, record: MemoryRecord) {
        guard let initialMediaAssetID else {
            imageViewerSelection = PaeoniaImageViewerSelection(image: image)
            return
        }

        var items = visibleMedia(for: record).map { media in
            imageViewerItem(for: media, initialMediaAssetID: initialMediaAssetID, image: image)
        }

        if !items.contains(where: { $0.id == initialMediaAssetID.uuidString }) {
            items.insert(PaeoniaImageViewerItem(id: initialMediaAssetID, image: image), at: 0)
        }

        imageViewerSelection = PaeoniaImageViewerSelection(
            items: items,
            initialItemID: initialMediaAssetID.uuidString
        )
    }

    private func imageViewerItem(
        for media: MemoryMediaSnapshot,
        initialMediaAssetID: UUID,
        image: UIImage
    ) -> PaeoniaImageViewerItem {
        let mediaAssetID = media.mediaAssetID
        let provider = MemoryMediaImageProviderFactory.shared
        let initialImage = mediaAssetID == initialMediaAssetID ? image : loadedImagesByMediaAssetID[mediaAssetID]

        return PaeoniaImageViewerItem(id: mediaAssetID, image: initialImage) {
            guard let data = await provider?.imageData(for: mediaAssetID) else {
                return nil
            }
            return UIImage(data: data)
        }
    }

    private func saveMemoryEdits(
        record: MemoryRecord,
        title: String,
        date: String,
        note: String,
        photos: [Data],
        removedMedia: [MemoryMediaSnapshot]
    ) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        var latestRecord = viewModel.record(for: record.snapshot.memoryID) ?? record

        if trimmedTitle != (latestRecord.snapshot.title ?? "") || date != latestRecord.snapshot.memoryDate {
            guard await viewModel.updateDetails(for: latestRecord, title: trimmedTitle, date: date) else {
                return false
            }
            latestRecord = viewModel.record(for: record.snapshot.memoryID) ?? latestRecord
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty, trimmedNote != (latestRecord.snapshot.ownNote?.body ?? "") {
            guard await viewModel.saveNote(for: latestRecord, body: trimmedNote) else {
                return false
            }
            latestRecord = viewModel.record(for: record.snapshot.memoryID) ?? latestRecord
        }

        for media in removedMedia {
            guard await viewModel.removePhoto(from: latestRecord, media: media) else {
                return false
            }
            latestRecord = viewModel.record(for: record.snapshot.memoryID) ?? latestRecord
        }

        if !photos.isEmpty {
            guard await viewModel.addPhotos(to: latestRecord, photos: photos) else {
                return false
            }
        }

        return true
    }
}
