import SwiftUI
import UIKit

/// Square thumbnail for a photo picked in the memory editor but not yet saved. Decodes
/// a small version off the main actor instead of decoding the full camera photo in `body`.
struct MemoryStagedPhotoThumbnail: View {
    let photo: MemoryDraftPhoto
    let size: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.paeoniaSurfaceSecondary
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: photo.id) {
                let loaded = await MemoryImageDecoding.downsample(
                    photo.data,
                    maxPixelSize: Int((size * displayScale).rounded(.up))
                )
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
