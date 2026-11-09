import SwiftUI
import UIKit

/// A story photo at full size, fitted to the screen. Uses the memory photo download and
/// cache, since a story photo is stored the same way. A failed photo retries on tap.
struct StoryPhotoView: View {
    let mediaAssetID: UUID
    /// Called once the photo shows, so the viewer only starts its timer then.
    var onLoaded: () -> Void = {}

    @State private var load = ImageLoad<UUID>.loading

    /// The longest side a story photo is decoded at for the screen.
    static let maxPixelSize = 2_048

    init(mediaAssetID: UUID, onLoaded: @escaping () -> Void = {}) {
        self.mediaAssetID = mediaAssetID
        self.onLoaded = onLoaded
        if let cached = MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: Self.maxPixelSize) {
            _load = State(initialValue: .loaded(mediaAssetID, cached))
        }
    }

    var body: some View {
        ZStack {
            if let image = load.image(for: mediaAssetID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear(perform: onLoaded)
            } else if load.hasFailed(for: mediaAssetID) {
                Button {
                    Task { await loadPhoto() }
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
        .task(id: mediaAssetID) { await loadPhoto() }
    }

    private func loadPhoto() async {
        if load.image(for: mediaAssetID) != nil { return }
        if let cached = MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: Self.maxPixelSize) {
            load = .loaded(mediaAssetID, cached)
            return
        }
        load = .loading
        var decoded: UIImage?
        if let data = await MemoryMediaImageProviderFactory.shared?.imageData(for: mediaAssetID) {
            decoded = await MemoryImageDecoding.downsample(data, maxPixelSize: Self.maxPixelSize)
        }
        guard !Task.isCancelled else { return }
        if let decoded {
            MemoryImageDecoding.store(decoded, for: mediaAssetID, maxPixelSize: Self.maxPixelSize)
        }
        // A downloaded photo fades in over the spinner. A cached one shows at once above.
        withAnimation(PaeoniaMotion.stateChange) {
            load = ImageLoad(decoded, for: mediaAssetID)
        }
    }
}
