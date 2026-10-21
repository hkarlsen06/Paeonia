import UIKit

/// Decoded profile photos and answer photos, kept in memory by media asset id. Views
/// read it when they are created, so a photo they showed before is in the very first
/// frame instead of fading in again. A chat list rebuilds its rows often, and each
/// rebuild would otherwise flash the placeholder.
nonisolated enum PaeoniaImageMemoryCache {
    /// NSCache is thread safe, so sharing this one instance across actors is safe.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func image(for mediaAssetID: UUID?) -> UIImage? {
        mediaAssetID.flatMap { image(forKey: $0.uuidString) }
    }

    static func store(_ image: UIImage, for mediaAssetID: UUID) {
        store(image, forKey: mediaAssetID.uuidString)
    }

    /// For images without a media asset id, such as a chat photo still sending, or a
    /// smaller copy kept for one display size.
    static func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, forKey key: String) {
        // Cost is the decoded size in bytes, which is what the limit counts.
        let cost = image.cgImage.map { $0.width * $0.height * 4 } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Drops every size kept for a media asset, such as the full image and the chat copy.
    static func remove(mediaAssetID: UUID) {
        cache.removeObject(forKey: mediaAssetID.uuidString as NSString)
        cache.removeObject(forKey: "chat-\(mediaAssetID.uuidString)" as NSString)
    }

    /// Called by the privacy cleanup together with the on-disk caches.
    static func removeAll() {
        cache.removeAllObjects()
    }
}
