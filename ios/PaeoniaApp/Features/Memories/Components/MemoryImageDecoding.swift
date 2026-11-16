import ImageIO
import UIKit

/// Decodes memory photos at display size and keeps the results in memory, so
/// scrolling the timeline never decodes a full camera photo on the main thread.
nonisolated enum MemoryImageDecoding {
    /// Views read the cache in `init`, before the environment's display scale exists, so
    /// pixel sizes use a fixed 3x scale. 2x screens decode a little more than they need.
    private static let referenceScale: CGFloat = 3
    private static let maxPixelSizeLimit = 2_048

    private static let cache = PurgeableImageCache()

    /// Read before loading a photo to store, so a privacy purge since keeps it out.
    static var generation: PurgeableImageCache.Generation {
        cache.generation
    }

    /// Longest-side pixel size for an aspect-fill photo in a frame this many points tall.
    /// Frames are wider than tall, so 1.5x the height covers the width in practice.
    static func maxPixelSize(forHeight height: CGFloat) -> Int {
        min(Int((max(height * 1.5, 160) * referenceScale).rounded(.up)), maxPixelSizeLimit)
    }

    static func cachedImage(for mediaAssetID: UUID, maxPixelSize: Int) -> UIImage? {
        cache.image(forKey: key(mediaAssetID, maxPixelSize))
    }

    /// Drops every decoded photo. The privacy purge calls this on sign-out and when a relationship ends.
    static func removeAll() {
        cache.removeAll()
    }

    static func remove(_ mediaAssetID: UUID, maxPixelSize: Int) {
        cache.remove(forKey: key(mediaAssetID, maxPixelSize))
    }

    static func store(
        _ image: UIImage,
        for mediaAssetID: UUID,
        maxPixelSize: Int,
        generation: PurgeableImageCache.Generation
    ) {
        cache.store(image, forKey: key(mediaAssetID, maxPixelSize), generation: generation)
    }

    /// Decodes `data` straight to a thumbnail whose longest side is at most
    /// `maxPixelSize`, without ever building the full-size bitmap. Runs off the main actor.
    @concurrent
    static func downsample(_ data: Data, maxPixelSize: Int) async -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func key(_ mediaAssetID: UUID, _ maxPixelSize: Int) -> String {
        "\(mediaAssetID.uuidString)-\(maxPixelSize)"
    }
}
