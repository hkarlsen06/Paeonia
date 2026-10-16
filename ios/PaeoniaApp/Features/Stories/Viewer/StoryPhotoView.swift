import SwiftUI
import UIKit

/// A story photo at full size, fitted to the screen. Uses the memory photo download and
/// cache, since a story photo is stored the same way. A failed photo retries on tap.
struct StoryPhotoView: View {
    let mediaAssetID: UUID
    /// Called once the photo shows, so the viewer only starts its timer then.
    var onLoaded: () -> Void = {}

    @State private var loaded: (id: UUID, image: UIImage)?
    @State private var didFail = false

    /// The longest side a story photo is decoded at for the screen.
    static let maxPixelSize = 2_048

    init(mediaAssetID: UUID, onLoaded: @escaping () -> Void = {}) {
        self.mediaAssetID = mediaAssetID
        self.onLoaded = onLoaded
        if let cached = MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: Self.maxPixelSize) {
            _loaded = State(initialValue: (id: mediaAssetID, image: cached))
        }
    }

    var body: some View {
        ZStack {
            if let loaded, loaded.id == mediaAssetID {
                Image(uiImage: loaded.image)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear(perform: onLoaded)
            } else if didFail {
                Button {
                    Task { await load() }
                } label: {
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .accessibilityHidden(true)
                        Text(.storiesViewerPhotoFailed)
                            .font(PaeoniaTypography.caption)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: mediaAssetID) { await load() }
    }

    private func load() async {
        if let loaded, loaded.id == mediaAssetID { return }
        if let cached = MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: Self.maxPixelSize) {
            loaded = (id: mediaAssetID, image: cached)
            return
        }
        didFail = false
        var decoded: UIImage?
        if let data = await MemoryMediaImageProviderFactory.shared?.imageData(for: mediaAssetID) {
            decoded = await MemoryImageDecoding.downsample(data, maxPixelSize: Self.maxPixelSize)
        }
        guard !Task.isCancelled else { return }
        if let decoded {
            MemoryImageDecoding.store(decoded, for: mediaAssetID, maxPixelSize: Self.maxPixelSize)
            loaded = (id: mediaAssetID, image: decoded)
        } else {
            didFail = true
        }
    }
}
