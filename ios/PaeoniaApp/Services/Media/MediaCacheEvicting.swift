import Foundation

nonisolated protocol MediaCacheEvicting: Sendable {
    /// Removes the cached files of media this phone no longer shows, because one of the
    /// partners deleted it. Called by the store that learns of the delete.
    func evict(mediaAssetIDs: [UUID]) async
}
