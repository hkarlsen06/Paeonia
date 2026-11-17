import Foundation

/// Gets the photos and videos of a memory save ready to queue. Each photo is compressed off
/// the main actor, and each item gets its ids here, so the photo or video goes into the local
/// caches under its asset id and the saved memory shows it before it uploads. The queued
/// create or attach uploads them (`MemoryQueuedUploads`), so a save works without a connection.
///
/// A pick keeps its ids when the person tries the save again, so a retry after a save that
/// partly went through does not queue the same photo twice.
final class MemoryMediaPreparation {
    struct Prepared {
        let snapshots: [MemoryMediaSnapshot]
        let uploads: [MemoryQueuedUpload]
    }

    private struct Key: Hashable {
        let draftMediaID: UUID
        let accessibilityText: String
    }

    private let imageCache: (any MemoryMediaImageCacheWriting)?
    private let operationProvider: any SyncClientOperationProviding
    private var prepared: [Key: MemoryQueuedUpload] = [:]

    init(imageCache: (any MemoryMediaImageCacheWriting)?, operationProvider: any SyncClientOperationProviding) {
        self.imageCache = imageCache
        self.operationProvider = operationProvider
    }

    /// Forgets the picks of a save that went through, or of the person who signed out.
    func reset() {
        prepared = [:]
    }

    /// Returns nil when a photo cannot be read, so nothing is saved without it.
    func prepare(
        _ media: [MemoryDraftMedia],
        coupleID: UUID,
        ownerUserID: UUID,
        startingSortOrder: Int
    ) async -> Prepared? {
        // Read before the caches are written, so a purge meanwhile keeps the videos out.
        let videoGeneration = await VideoFileCache.shared?.privacyGeneration ?? 0
        var snapshots: [MemoryMediaSnapshot] = []
        var uploads: [MemoryQueuedUpload] = []
        for (index, item) in media.enumerated() {
            let key = Key(draftMediaID: item.id, accessibilityText: item.accessibilityText)
            let upload: MemoryQueuedUpload
            if let earlier = prepared[key], earlier.coupleID == coupleID {
                upload = earlier
            } else {
                guard let made = await prepare(item, coupleID: coupleID, videoGeneration: videoGeneration) else {
                    return nil
                }
                upload = made
                prepared[key] = made
            }
            uploads.append(upload)
            snapshots.append(MemoryMediaSnapshot(
                memoryMediaID: upload.memoryMediaID,
                mediaAssetID: upload.mediaAssetID,
                ownerUserID: ownerUserID,
                kind: item.video == nil ? .image : .video,
                durationMs: item.video?.durationMs,
                sortOrder: startingSortOrder + index,
                updatedAt: Date(),
                accessibilityText: item.accessibilityText
            ))
        }
        return Prepared(snapshots: snapshots, uploads: uploads)
    }

    private func prepare(
        _ item: MemoryDraftMedia, coupleID: UUID, videoGeneration: UInt64
    ) async -> MemoryQueuedUpload? {
        let mediaAssetID = UUID()
        let local: MemoryQueuedUpload.Local
        let size: (width: Int, height: Int)
        switch item.content {
        case .photo(let photo):
            guard let compressed = await Self.compress(photo) else { return nil }
            local = .photo(compressed.data, mimeType: compressed.mediaType, fileExtension: compressed.fileExtension)
            size = (compressed.width, compressed.height)
            await imageCache?.cacheImageData(compressed.data, for: mediaAssetID)
        case .video(let video):
            local = .video(fileName: video.fileURL.lastPathComponent)
            size = (video.width, video.height)
            // The person plays their own copy, before and after it uploads.
            await VideoFileCache.shared?.store(video.fileURL, for: mediaAssetID, privacyGeneration: videoGeneration)
        }
        return MemoryQueuedUpload(
            mediaAssetID: mediaAssetID,
            memoryMediaID: UUID(),
            coupleID: coupleID,
            local: local,
            width: size.width,
            height: size.height,
            durationMs: item.video?.durationMs,
            accessibilityText: item.accessibilityText,
            reserveOperation: operationProvider.makeOperation(),
            finalizeOperation: operationProvider.makeOperation()
        )
    }

    /// Compressing a full camera photo takes a noticeable moment, so it runs off the
    /// main actor and the save spinner keeps moving.
    @concurrent
    private nonisolated static func compress(_ photo: Data) async -> ImageCompressor.CompressedImage? {
        ImageCompressor.compress(photo)
    }
}
