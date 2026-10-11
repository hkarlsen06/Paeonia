import SwiftUI
import UIKit

/// Square thumbnail for a photo picked in the memory editor but not yet saved. Decodes
/// a small version off the main actor instead of decoding the full camera photo in `body`.
struct MemoryStagedPhotoThumbnail: View {
    let data: Data
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
            .task(id: data) {
                // Photos are keyed by position in the editor, so clear the old one first
                // rather than showing the previous photo while the new one decodes.
                image = nil
                let loaded = await MemoryImageDecoding.downsample(
                    data,
                    maxPixelSize: Int((size * displayScale).rounded(.up))
                )
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
