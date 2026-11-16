import PhotosUI
import SwiftUI
import UIKit

/// The photos part of the memory form: photos and videos already on the memory, ones
/// picked for this save, placeholders while picked ones load, and the library and camera
/// buttons. Each partner can add up to five photos and videos to a memory.
struct MemoryEditorPhotosField: View {
    @Binding var media: [MemoryDraftMedia]
    @Binding var existingDescriptions: [UUID: String]
    @Binding var removedExistingMediaIDs: Set<UUID>
    /// Picked photos still loading and videos still being prepared. The form can't save
    /// until they're in.
    @Binding var loadingCount: Int
    /// Set when the person threw the form away. A pick that finishes later is dropped.
    @Binding var isDiscarded: Bool
    let existingMedia: [MemoryMediaSnapshot]
    let currentUserID: UUID?
    let allowsPhotos: Bool
    let isSaving: Bool

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?
    @State private var videoViewerItem: PaeoniaVideoViewerItem?

    /// Photos and videos together.
    static let maxPhotosPerPartner = 5
    private let thumbnailSize: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if !visibleExistingMedia.isEmpty || !media.isEmpty || loadingCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PaeoniaSpacing.space8) {
                        ForEach(visibleExistingMedia, id: \.memoryMediaID) { media in
                            existingPhotoEditor(media)
                        }
                        ForEach(media) { item in
                            stagedMediaEditor(item)
                        }
                        ForEach(0..<loadingCount, id: \.self) { _ in
                            loadingThumbnail
                        }
                    }
                }
            }

            if allowsPhotos, remainingPhotoSlots > 0 {
                pickerControls
            }
        }
        .onChange(of: pickerItems) { _, items in
            loadPickedMedia(items)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            DailyCameraPicker(onCapture: appendCapturedPhoto)
                .ignoresSafeArea()
        }
        .paeoniaImageViewer(selection: $imageViewerSelection)
        .paeoniaVideoViewer(item: $videoViewerItem)
    }

    private func existingPhotoEditor(_ media: MemoryMediaSnapshot) -> some View {
        VStack {
            existingThumbnail(media)
            if media.ownerUserID == currentUserID {
                PhotoDescriptionField(text: Binding(
                    get: {
                        existingDescriptions[media.mediaAssetID] ?? media.accessibilityText ?? ""
                    },
                    set: { existingDescriptions[media.mediaAssetID] = $0 }
                ))
                .frame(width: 200)
                .disabled(isSaving)
            }
        }
    }

    private func stagedMediaEditor(_ item: MemoryDraftMedia) -> some View {
        VStack {
            stagedThumbnail(item)
            PhotoDescriptionField(text: Binding(
                get: { media.first { $0.id == item.id }?.accessibilityText ?? "" },
                set: { value in
                    if let index = media.firstIndex(where: { $0.id == item.id }) {
                        media[index].accessibilityText = value
                    }
                }
            ))
            .frame(width: 200)
            .disabled(isSaving)
        }
    }

    private func existingThumbnail(_ media: MemoryMediaSnapshot) -> some View {
        ZStack(alignment: .topTrailing) {
            MemoryMediaImageView(
                media: media.media,
                accessibilityText: media.accessibilityText,
                height: thumbnailSize,
                cornerRadius: PaeoniaRadius.radius12
            )
            .frame(width: thumbnailSize)

            if media.ownerUserID == currentUserID {
                removeButton(isVideo: media.isVideo) {
                    animateStrip { _ = removedExistingMediaIDs.insert(media.memoryMediaID) }
                }
            }
        }
    }

    private func stagedThumbnail(_ item: MemoryDraftMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            MemoryStagedMediaThumbnail(item: item, size: thumbnailSize, cornerRadius: PaeoniaRadius.radius12)
                .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
                .onTapGesture {
                    presentStaged(item)
                }
                .accessibilityLabel(Text(verbatim: stagedAccessibilityLabel(item)))
                .accessibilityAddTraits(.isButton)

            removeButton(isVideo: item.video != nil) {
                animateStrip { media.removeAll { $0.id == item.id } }
                MemoryDraftMedia.deleteVideoFiles(of: [item])
            }
        }
    }

    private func stagedAccessibilityLabel(_ item: MemoryDraftMedia) -> String {
        guard let video = item.video else { return PhotoDescription.label(item.accessibilityText) }
        return VideoBadge.accessibilityLabel(durationMs: video.durationMs, description: item.accessibilityText)
    }

    private var loadingThumbnail: some View {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            .fill(.paeoniaSurfaceSecondary)
            .frame(width: thumbnailSize, height: thumbnailSize)
            .overlay { ProgressView() }
            .accessibilityHidden(true)
    }

    private func removeButton(isVideo: Bool, _ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space4)
        .accessibilityLabel(Text(isVideo ? .memoriesVideoRemove : .memoriesPhotoRemove))
        .disabled(isSaving)
    }

    private var pickerControls: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, remainingPhotoSlots),
                matching: .any(of: [.images, .videos])
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
        .disabled(isSaving)
    }

    private var visibleExistingMedia: [MemoryMediaSnapshot] {
        existingMedia.filter { !removedExistingMediaIDs.contains($0.memoryMediaID) }
    }

    private var remainingPhotoSlots: Int {
        let ownVisible = visibleExistingMedia.filter { $0.ownerUserID == currentUserID }.count
        return max(0, Self.maxPhotosPerPartner - ownVisible - media.count - loadingCount)
    }

    private func loadPickedMedia(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let picked = Array(items.prefix(remainingPhotoSlots))
        pickerItems = []
        animateStrip { loadingCount += picked.count }
        let ticket = VideoPreparation.ticket()
        Task {
            let (loaded, failure) = await Self.load(picked, ticket: ticket)
            guard !isDiscarded, VideoPreparation.isCurrent(ticket) else {
                MemoryDraftMedia.deleteVideoFiles(of: loaded)
                loadingCount -= picked.count
                return
            }
            // One append, so a saved draft writes its photo files once.
            animateStrip {
                loadingCount -= picked.count
                media.append(contentsOf: loaded)
            }
            if let failure {
                bannerCenter.show(.error(message: String(localized: failure)))
            }
        }
    }

    /// A photo loads as data. A video is made small enough to send, which can take a while
    /// for a long one. Also returns what to tell about the picks that failed.
    private static func load(
        _ items: [PhotosPickerItem],
        ticket: VideoPreparation.Ticket
    ) async -> ([MemoryDraftMedia], LocalizedStringResource?) {
        var loaded: [MemoryDraftMedia] = []
        var videoFailure: (any Error)?
        var photoFailed = false
        for item in items {
            if item.isVideo {
                do {
                    loaded.append(MemoryDraftMedia(content: .video(try await VideoPreparation.prepare(
                        item, into: MemoryDraftMedia.videoDirectoryURL(), cap: .threeMinutes, ticket: ticket
                    ))))
                } catch {
                    // A video that is too long is the most useful to tell about.
                    if videoFailure == nil || error as? VideoTranscodeError == .tooLong { videoFailure = error }
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(MemoryDraftMedia(content: .photo(data)))
            } else {
                photoFailed = true
            }
        }
        let failure = videoFailure.flatMap { VideoLengthCap.threeMinutes.message(for: $0) }
            ?? (photoFailed ? .memoriesEditorPhotoLoadFailed : nil)
        return (loaded, failure)
    }

    private func appendCapturedPhoto(_ data: Data) {
        guard allowsPhotos, remainingPhotoSlots > 0 else { return }
        animateStrip { media.append(MemoryDraftMedia(content: .photo(data))) }
    }

    /// Tiles fade in and out and the strip and the fields below glide to their new
    /// place. The animation wraps the write, so it reaches the form outside this view.
    private func animateStrip(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange, change)
    }

    private func presentStaged(_ item: MemoryDraftMedia) {
        switch item.content {
        case .photo(let data):
            guard let uiImage = UIImage(data: data) else { return }
            imageViewerSelection = PaeoniaImageViewerSelection(image: uiImage)
        case .video(let video):
            let fileURL = video.fileURL
            videoViewerItem = PaeoniaVideoViewerItem(id: item.id.uuidString) { PaeoniaVideoFile(url: fileURL) }
        }
    }
}
