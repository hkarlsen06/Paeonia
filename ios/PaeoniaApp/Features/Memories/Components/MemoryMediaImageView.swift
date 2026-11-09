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
struct MemoryMediaImageView: View {
    let mediaAssetID: UUID?
    let accessibilityText: String?
    let provider: (any MemoryMediaImageProviding)?
    let height: CGFloat
    let cornerRadius: CGFloat
    let allowsViewing: Bool
    let onTapImage: ((UUID?, UIImage) -> Void)?

    @State private var load = ImageLoad<UUID?>.loading
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    init(
        mediaAssetID: UUID?,
        accessibilityText: String? = nil,
        provider: (any MemoryMediaImageProviding)? = MemoryMediaImageProviderFactory.shared,
        height: CGFloat = 240,
        cornerRadius: CGFloat = PaeoniaRadius.radius16,
        allowsViewing: Bool = true,
        onTapImage: ((UUID?, UIImage) -> Void)? = nil
    ) {
        self.mediaAssetID = mediaAssetID
        self.accessibilityText = accessibilityText
        self.provider = provider
        self.height = height
        self.cornerRadius = cornerRadius
        self.allowsViewing = allowsViewing
        self.onTapImage = onTapImage

        // Seed from the cache so a cached photo is in the very first frame, with no spinner.
        if let mediaAssetID,
           let cached = MemoryImageDecoding.cachedImage(
               for: mediaAssetID,
               maxPixelSize: MemoryImageDecoding.maxPixelSize(forHeight: height)
           ) {
            _load = State(initialValue: .loaded(mediaAssetID, cached))
        }
    }

    var body: some View {
        imageSurface
            .accessibilityLabel(Text(verbatim: PhotoDescription.label(accessibilityText)))
            .paeoniaImageViewer(selection: $imageViewerSelection)
    }

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
            Image(systemName: "photo")
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
        var decoded: UIImage?
        if let data = await provider.imageData(for: mediaAssetID) {
            decoded = await MemoryImageDecoding.downsample(data, maxPixelSize: maxPixelSize)
        }
        if let decoded {
            MemoryImageDecoding.store(decoded, for: mediaAssetID, maxPixelSize: maxPixelSize)
        }

        // A cancelled load (the view moved to another asset or went away) must not
        // report a failure or overwrite newer state.
        guard !Task.isCancelled else { return }
        load = ImageLoad(decoded, for: mediaAssetID)
    }

    private func handleTap() {
        guard allowsViewing else { return }

        if let mediaAssetID, let image {
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
