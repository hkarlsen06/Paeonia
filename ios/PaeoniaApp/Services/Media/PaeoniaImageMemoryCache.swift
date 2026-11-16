import UIKit

/// Decoded profile photos and answer photos, kept in memory by media asset id. Views
/// read it when they are created, so a photo they showed before is in the very first
/// frame instead of fading in again. A chat list rebuilds its rows often, and each
/// rebuild would otherwise flash the placeholder.
nonisolated enum PaeoniaImageMemoryCache {
    private static let cache = PurgeableImageCache()

    /// Read before loading an image to store, so a privacy purge since keeps it out.
    static var generation: PurgeableImageCache.Generation {
        cache.generation
    }

    static func image(for mediaAssetID: UUID?) -> UIImage? {
        mediaAssetID.flatMap { image(forKey: $0.uuidString) }
    }

    static func store(_ image: UIImage, for mediaAssetID: UUID, generation: PurgeableImageCache.Generation) {
        store(image, forKey: mediaAssetID.uuidString, generation: generation)
    }

    /// For images without a media asset id, such as a chat photo still sending, or a
    /// smaller copy kept for one display size.
    static func image(forKey key: String) -> UIImage? {
        cache.image(forKey: key)
    }

    static func store(_ image: UIImage, forKey key: String, generation: PurgeableImageCache.Generation) {
        cache.store(image, forKey: key, generation: generation)
    }

    /// Drops every picture kept for a media asset: the full image, the chat copy and a
    /// chat video's first frame.
    static func remove(mediaAssetID: UUID) {
        for prefix in ["", "chat-", "chat-video-"] {
            cache.remove(forKey: "\(prefix)\(mediaAssetID.uuidString)")
        }
    }

    /// Called by the privacy cleanup together with the on-disk caches.
    static func removeAll() {
        cache.removeAll()
    }
}
