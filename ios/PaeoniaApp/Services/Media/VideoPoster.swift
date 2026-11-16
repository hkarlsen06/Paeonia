import AVFoundation
import UIKit

/// The first frame of a video, for a bubble or a tile that shows the video before
/// anyone plays it. Lists show this picture only, never a live player.
nonisolated enum VideoPoster {
    /// `maxPixelSize` bounds the longer side, so a poster never decodes the full frame.
    /// Returns nil when the file has no frame to show.
    @concurrent
    static func image(for fileURL: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame)
    }

    /// The first frame of an uploaded video. The file downloads once, through the cache
    /// the full-screen player reads too.
    static func image(forMediaAsset mediaAssetID: UUID, maxPixelSize: CGFloat) async -> UIImage? {
        guard let file = try? await VideoFileCache.shared?.fileURL(for: mediaAssetID) else { return nil }
        return await image(for: file, maxPixelSize: maxPixelSize)
    }
}
