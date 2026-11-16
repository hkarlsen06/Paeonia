import SwiftUI
import UIKit

/// Shared provider for memory photos, created once. Nil when the Convex client
/// can't be configured (previews/tests), in which case photos show a quiet
/// placeholder instead of loading.
nonisolated enum MemoryMediaImageProviderFactory {
    static let shared: (any MemoryMediaImageProviding)? = MemoryMediaImageService.shared
}

/// Loads and shows a memory photo. Fetches a signed download once, decodes it at display
/// size off the main actor, and keeps the result in `MemoryImageDecoding`'s cache so a
/// card that scrolls back into view shows its photo right away. Shows a quiet placeholder
/// while loading or if it can't be fetched, and a tap on the failed state tries again. The
/// surface rectangle owns the size so a `scaledToFill` photo crops within these bounds
/// rather than widening its container (same approach as `DailyAnswerImageView`).
/// A video shows its first frame with `VideoBadge`, and a tap plays it full screen.
struct MemoryMediaImageView: View {
    let media: MediaReference?
    let accessibilityText: String?
    let provider: (any MemoryMediaImageProviding)?
    let height: CGFloat
    let cornerRadius: CGFloat
    let allowsViewing: Bool
    let onTapImage: ((UUID?, UIImage) -> Void)?

    @State private var load = ImageLoad<UUID?>.loading
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?
    @State private var videoViewerItem: PaeoniaVideoViewerItem?

    init(
        media: MediaReference?,
        accessibilityText: String? = nil,
        provider: (any MemoryMediaImageProviding)? = MemoryMediaImageProviderFactory.shared,
        height: CGFloat = 240,
        cornerRadius: CGFloat = PaeoniaRadius.radius16,
        allowsViewing: Bool = true,
        onTapImage: ((UUID?, UIImage) -> Void)? = nil
    ) {
        self.media = media
        self.accessibilityText = accessibilityText
        self.provider = provider
        self.height = height
        self.cornerRadius = cornerRadius
        self.allowsViewing = allowsViewing
        self.onTapImage = onTapImage

        // Seed from the cache so a cached photo is in the very first frame, with no spinner.
        if let mediaAssetID = media?.assetID,
           let cached = MemoryImageDecoding.cachedImage(
               for: mediaAssetID,
               maxPixelSize: MemoryImageDecoding.maxPixelSize(forHeight: height)
           ) {
            _load = State(initialValue: .loaded(mediaAssetID, cached))
        }
    }

    var body: some View {
        imageSurface
            .accessibilityLabel(accessibilityLabel)
            .paeoniaImageViewer(selection: $imageViewerSelection)
            .paeoniaVideoViewer(item: $videoViewerItem)
    }

    private var accessibilityLabel: Text {
        guard isVideo else { return Text(verbatim: PhotoDescription.label(accessibilityText)) }
        return Text(verbatim: VideoBadge.accessibilityLabel(
            durationMs: videoDurationMs,
            description: accessibilityText
        ))
    }

    private var mediaAssetID: UUID? { media?.assetID }
    private var isVideo: Bool { media?.isVideo ?? false }
    private var videoDurationMs: Int? { media?.videoDurationMs }

    private var image: UIImage? { load.image(for: mediaAssetID) }
    private var didFail: Bool { load.hasFailed(for: mediaAssetID) }

    private var maxPixelSize: Int {
        MemoryImageDecoding.maxPixelSize(forHeight: height)
    }

    @ViewBuilder
    private var imageSurface: some View {
        if allowsViewing {
            // The button trait is conditional (not while the spinner shows), which the rule can't see.
            // swiftlint:disable:next accessibility_trait_for_button
            baseImageSurface
                .contentShape(imageShape)
                .onTapGesture { handleTap() }
                .accessibilityAddTraits(image != nil || didFail ? .isButton : [])
                .accessibilityHint(didFail ? Text(.memoriesPhotoRetryHint) : Text(verbatim: ""))
        } else {
            baseImageSurface
        }
    }

    private var baseImageSurface: some View {
        imageShape
            .fill(.paeoniaSurfaceSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { content }
            // On the frame, not the photo: a filled photo reaches past the visible corner.
            .overlay(alignment: .bottomLeading) {
                if isVideo, image != nil {
                    VideoBadge(durationMs: videoDurationMs)
                        .padding(PaeoniaSpacing.space8)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(imageShape)
            // The loaded photo (or the failure glyph) fades in over the quiet
            // placeholder instead of snapping into the frame when the download lands.
            .animation(PaeoniaMotion.stateChange, value: image != nil)
            .animation(PaeoniaMotion.stateChange, value: didFail)
            .task(id: mediaAssetID) { await loadPhoto() }
    }

    private var imageShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else if didFail {
            Image(systemName: isVideo ? "video" : "photo")
                .font(.largeTitle)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
        }
    }

    private func loadPhoto() async {
        guard image == nil else { return }

        guard let mediaAssetID, let provider else {
            load = .failed(mediaAssetID)
            return
        }

        // Covers a reused view whose asset changed to one that is already decoded.
        if let cached = MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: maxPixelSize) {
            load = .loaded(mediaAssetID, cached)
            return
        }

        load = .loading
        let generation = MemoryImageDecoding.generation
        var decoded: UIImage?
        if isVideo {
            decoded = await VideoPoster.image(forMediaAsset: mediaAssetID, maxPixelSize: CGFloat(maxPixelSize))
        } else if let data = await provider.imageData(for: mediaAssetID) {
            decoded = await MemoryImageDecoding.downsample(data, maxPixelSize: maxPixelSize)
        }
        if let decoded {
            MemoryImageDecoding.store(decoded, for: mediaAssetID, maxPixelSize: maxPixelSize, generation: generation)
        }

        // A cancelled load (the view moved to another asset or went away) must not
        // report a failure or overwrite newer state.
        guard !Task.isCancelled else { return }
        load = ImageLoad(decoded, for: mediaAssetID)
    }

    private func handleTap() {
        guard allowsViewing else { return }

        if isVideo, let mediaAssetID, image != nil {
            videoViewerItem = PaeoniaVideoViewerItem(id: mediaAssetID.uuidString) {
                guard let cache = VideoFileCache.shared else { throw VideoFileCacheError.unavailable }
                return PaeoniaVideoFile(
                    url: try await cache.fileURL(for: mediaAssetID, priority: .playback), mediaAssetID: mediaAssetID
                )
            }
        } else if let mediaAssetID, let image {
            presentImageViewer(mediaAssetID: mediaAssetID, image: image)
        } else if didFail {
            Task { await loadPhoto() }
        }
    }

    private func presentImageViewer(mediaAssetID: UUID, image: UIImage) {
        if let onTapImage {
            onTapImage(mediaAssetID, image)
        } else if let provider {
            // The viewer loads the full-resolution photo itself. `image` is only a
            // thumbnail, which looks soft when zoomed.
            imageViewerSelection = PaeoniaImageViewerSelection(
                items: [
                    PaeoniaImageViewerItem(
                        id: mediaAssetID,
                        accessibilityText: PhotoDescription.label(accessibilityText),
                        imageLoader: {
                            guard let data = await provider.imageData(for: mediaAssetID) else { return nil }
                            return UIImage(data: data)
                        }
                    )
                ],
                initialItemID: mediaAssetID.uuidString
            )
        } else {
            imageViewerSelection = PaeoniaImageViewerSelection(
                items: [PaeoniaImageViewerItem(
                    id: mediaAssetID, image: image, accessibilityText: PhotoDescription.label(accessibilityText)
                )], initialItemID: mediaAssetID.uuidString
            )
        }
    }
}
