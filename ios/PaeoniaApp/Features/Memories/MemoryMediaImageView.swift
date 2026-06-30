import SwiftUI
import UIKit

/// Shared provider for memory photos, created once. Nil when the Supabase client
/// can't be configured (previews/tests), in which case photos show a quiet
/// placeholder instead of loading.
nonisolated enum MemoryMediaImageProviderFactory {
    static let shared: (any MemoryMediaImageProviding)? = try? MemoryMediaImageService.live()
}

/// Loads and shows a memory photo. Fetches a signed download once, caches it, and
/// shows a quiet placeholder while loading or if it can't be fetched. The surface
/// rectangle owns the size so a `scaledToFill` photo crops within these bounds rather
/// than widening its container (same approach as `DailyAnswerImageView`).
struct MemoryMediaImageView: View {
    let mediaAssetID: UUID?
    var provider: (any MemoryMediaImageProviding)? = MemoryMediaImageProviderFactory.shared
    var height: CGFloat = 240
    var cornerRadius: CGFloat = PaeoniaRadius.radius16
    var allowsViewing = true
    var onTapImage: ((UUID?, UIImage) -> Void)?
    var onImageLoaded: ((UUID, UIImage) -> Void)?

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    var body: some View {
        imageSurface
            .accessibilityLabel(Text(.memoriesPhotoAccessibility))
            .accessibilityAddTraits(image != nil && allowsViewing ? .isButton : [])
            .paeoniaImageViewer(selection: $imageViewerSelection)
    }

    @ViewBuilder
    private var imageSurface: some View {
        if allowsViewing {
            baseImageSurface
                .contentShape(imageShape)
                .onTapGesture { presentImageViewer() }
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
            .task(id: mediaAssetID) { await load() }
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

    private func load() async {
        image = nil
        didFail = false

        guard let mediaAssetID, let provider else {
            didFail = true
            return
        }

        let data = await provider.imageData(for: mediaAssetID)
        if let data, let loaded = UIImage(data: data) {
            image = loaded
            onImageLoaded?(mediaAssetID, loaded)
        } else {
            didFail = true
        }
    }

    private func presentImageViewer() {
        guard allowsViewing, let image else { return }

        if let onTapImage {
            onTapImage(mediaAssetID, image)
        } else if let mediaAssetID {
            imageViewerSelection = PaeoniaImageViewerSelection(id: mediaAssetID, image: image)
        } else {
            imageViewerSelection = PaeoniaImageViewerSelection(image: image)
        }
    }
}
