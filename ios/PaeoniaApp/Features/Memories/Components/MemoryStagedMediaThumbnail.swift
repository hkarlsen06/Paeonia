import SwiftUI
import UIKit

/// Square thumbnail for a photo or video picked in the memory editor but not yet saved.
/// Decodes a small version off the main actor instead of decoding the full camera photo in
/// `body`. A video shows its first frame with `VideoBadge`.
struct MemoryStagedMediaThumbnail: View {
    let item: MemoryDraftMedia
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
            .overlay(alignment: .bottomLeading) {
                if let video = item.video {
                    VideoBadge(durationMs: video.durationMs)
                        .padding(PaeoniaSpacing.space4)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: item.id) {
                let maxPixelSize = Int((size * displayScale).rounded(.up))
                let loaded = switch item.content {
                case .photo(let data):
                    await MemoryImageDecoding.downsample(data, maxPixelSize: maxPixelSize)
                case .video(let video):
                    await VideoPoster.image(for: video.fileURL, maxPixelSize: CGFloat(maxPixelSize))
                }
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
