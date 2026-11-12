import AppIntents
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
    let mediaImageProvider: (any MemoryMediaImageProviding)?

    @Environment(\.dismiss) private var dismiss
    /// Names the visit the memory was made for. Nil leaves the visit out.
    @Environment(VisitsViewModel.self) private var visits: VisitsViewModel?

    /// The memory as it was when the edit sheet opened, and the sheet's item, so the sheet is
    /// built from it. Saving compares against it, so only what the person changed is sent, and
    /// the sheet keeps using it if the memory is deleted mid-edit so the typed text stays on screen.
    @State private var editing: EditedMemory?
    /// The memory the delete alert asks about, as it was when the alert opened. If it joins the
    /// partner's memory for its visit before the person confirms, the screen behind shows that
    /// memory, and the delete still acts on this one.
    @State private var deleting: MemoryRecord?
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?
    /// The media asset id of the photo the carousel shows. Nil shows the first.
    @State private var shownPhotoID: UUID?

    private let photoCarouselHeight: CGFloat = 320
    private let photoCarouselPageControlInset: CGFloat = PaeoniaSpacing.space40

    init(
        memoryID: UUID,
        currentUserID: UUID?,
        viewModel: MemoriesViewModel,
        mediaImageProvider: (any MemoryMediaImageProviding)? = MemoryMediaImageProviderFactory.shared
    ) {
        self.memoryID = memoryID
        self.currentUserID = currentUserID
        self.viewModel = viewModel
        self.mediaImageProvider = mediaImageProvider
    }

    private var record: MemoryRecord? {
        viewModel.record(for: memoryID)
    }

    var body: some View {
        Group {
            if let record {
                content(for: record)
            } else if let failure = viewModel.loadFailure {
                PaeoniaLoadFailureView(failure: failure, offlineMessage: .commonLoadFailedMessage) {
                    Button { Task { await viewModel.load() } } label: { Text(.commonTryAgain) }
                        .buttonStyle(PaeoniaSecondaryButtonStyle())
                }
            } else {
                // The memory was deleted (or never loaded); fall back to a blank surface
                // while the dismiss below takes effect.
                Color.paeoniaBackgroundPrimary
            }
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .onChange(of: record == nil) { _, isGone in
            guard isGone else { return }
            // Closing the screen now would also close the edit sheet and drop the
            // unsaved text. The sheet stays open and explains instead.
            if editing == nil { dismiss() }
        }
        .sheet(item: $editing, onDismiss: closeAfterRemoval) { editing in
            ExistingMemoryEditor(record: editing.record, currentUserID: currentUserID, viewModel: viewModel)
        }
        .alert(
            Text(.memoriesDeleteTitle),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { asked in
            Button(role: .cancel) {} label: { Text(.commonCancel) }
            Button(role: .destructive) {
                Task { await viewModel.deleteMemory(asked) }
            } label: {
                Text(.memoriesDeleteAction)
            }
        } message: { _ in
            Text(.memoriesDeleteMessage)
        }
        .paeoniaImageViewer(selection: $imageViewerSelection)
        .modifier(MemoryCelebration(memoryID: memoryID, viewModel: viewModel))
        .memoryOnScreenForSiri(
            record?.snapshot.memoryID ?? memoryID, title: record?.snapshot.title, viewModel: viewModel,
            shownPhotoID: $shownPhotoID
        )
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

                ReactionSection(target: .memory(record.snapshot.memoryID))

                MemoryCommentsSection(record: record, viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
            .paeoniaReadableWidth()
        }
    }

    private func photoGallery(for record: MemoryRecord) -> some View {
        let mediaItems = visibleMedia(for: record)
        let selection = Binding<UUID?>(
            get: { shownPhotoID ?? mediaItems.first?.mediaAssetID },
            set: { shownPhotoID = $0 }
        )
        return TabView(selection: selection) {
            ForEach(mediaItems, id: \.memoryMediaID) { media in
                MemoryMediaImageView(
                    mediaAssetID: media.mediaAssetID,
                    accessibilityText: media.accessibilityText,
                    provider: mediaImageProvider,
                    height: photoCarouselHeight,
                    cornerRadius: PaeoniaRadius.radius16,
                    onTapImage: { mediaAssetID, _ in
                        presentImageViewer(initialMediaAssetID: mediaAssetID, mediaItems: mediaItems)
                    }
                )
                .accessibilityIdentifier("memory.photo.\(media.mediaAssetID.uuidString)")
                .contextMenu {
                    savePhotoButton(for: media)
                }
                .accessibilityAction(named: Text(.memoriesPhotoSave)) {
                    Task { await viewModel.savePhotoToLibrary(mediaAssetID: media.mediaAssetID) }
                }
                .padding(.bottom, mediaItems.count > 1 ? photoCarouselPageControlInset : 0)
                .tag(Optional(media.mediaAssetID))
                .appEntityIdentifier(
                    EntityIdentifier(for: MemoryPhotoEntity.self, identifier: .saved(mediaAssetID: media.mediaAssetID))
                )
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
                    deleting = record
                } label: {
                    Label { Text(.memoriesDetailDelete) } icon: { Image(systemName: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel(Text(.memoriesDetailMenu))
            }
            .accessibilityIdentifier("memories.detail.menu")
            .disabled(record == nil)
        }
    }

    // MARK: - Actions

    private func openMemoryEditor() {
        guard let record else { return }
        editing = EditedMemory(record: record)
    }

    /// After the sheet closes on a memory that was deleted, there is nothing left to
    /// show, so leave the detail screen.
    private func closeAfterRemoval() {
        if record == nil { dismiss() }
    }

    /// Opens the full-screen viewer on the tapped photo, with every photo of the memory
    /// to swipe through. Each page loads the full-resolution photo itself; the carousel
    /// only holds smaller copies.
    private func presentImageViewer(initialMediaAssetID: UUID?, mediaItems: [MemoryMediaSnapshot]) {
        guard let initialMediaAssetID else { return }
        let provider = mediaImageProvider
        let items = mediaItems.map { media in
            let mediaAssetID = media.mediaAssetID
            return PaeoniaImageViewerItem(
                id: mediaAssetID, accessibilityText: PhotoDescription.label(media.accessibilityText)
            ) {
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

private struct EditedMemory: Identifiable {
    let record: MemoryRecord
    var id: UUID { record.snapshot.memoryID }
}

// MARK: - Derived

extension MemoryDetailView {
    private func header(for record: MemoryRecord) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Group {
                if let place = record.snapshot.place {
                    Text(verbatim: "\(dayStartUTC(for: record).formatted(MemoryDateStyle.long)) · \(place.nameAndCity)")
                } else {
                    Text(dayStartUTC(for: record), format: MemoryDateStyle.long)
                }
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaMemory)

            if let visit = visits?.state.visits.first(where: { $0.id == record.snapshot.visitID }) {
                Text(.memoriesDetailVisit(visit.dateRangeText()))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }

            Text(record.snapshot.title ?? "")
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .combine)
    }

    private func visibleMedia(for record: MemoryRecord) -> [MemoryMediaSnapshot] {
        record.snapshot.media.filter(\.isVisible).sortedForMemoryDisplay()
    }

    private func visibleBody(of note: MemoryNoteSnapshot?) -> String? {
        note?.visibleBody
    }

    private func dayStartUTC(for record: MemoryRecord) -> Date {
        MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
    }
}
