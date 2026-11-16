import UIKit

/// Decoded images kept in memory, which a privacy purge empties for good. A decode that
/// started before the purge finishes after it, so a writer reads `generation` before it
/// starts loading and `store` refuses its image once a purge ran since.
nonisolated final class PurgeableImageCache: @unchecked Sendable {
    /// Read before loading an image, and handed to `store` with it.
    struct Generation: Equatable, Sendable {
        fileprivate let count: Int
    }

    // NSCache is thread safe. `lock` guards `purges`, and holds while a store checks it
    // and while a purge empties the cache, so no store lands between the two.
    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var purges = 0

    init(totalCostLimit: Int = 64 * 1_024 * 1_024) {
        cache.totalCostLimit = totalCostLimit
    }

    var generation: Generation {
        lock.withLock { Generation(count: purges) }
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String, generation: Generation) {
        // Cost is the decoded size in bytes, which is what the limit counts.
        let cost = image.cgImage.map { $0.width * $0.height * 4 } ?? 0
        lock.withLock {
            guard generation.count == purges else { return }
            cache.setObject(image, forKey: key as NSString, cost: cost)
        }
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        lock.withLock {
            purges &+= 1
            cache.removeAllObjects()
        }
    }
}
