import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// How far a save has got through uploading its photos and videos, for the save button.
nonisolated struct MemoryMediaUploadProgress: Equatable, Sendable {
    /// 1-based number of the photo or video being sent now.
    let current: Int
    let total: Int
}

/// Sends the photos and videos of a memory save, one at a time. Photos are compressed off
/// the main actor, and videos were prepared when they were picked. One that went up before
/// a later one failed is reused when the person tries again within a few minutes, instead
/// of being sent twice.
@Observable
final class MemoryMediaUploads {
    private(set) var progress: MemoryMediaUploadProgress?

    private let uploader: (any MemoryMediaUploading)?
    private let imageCache: (any MemoryMediaImageCacheWriting)?
    private let operationProvider: any SyncClientOperationProviding
    private var uploaded: [Key: (result: MemoryMediaUploadResult, at: Date)] = [:]
    /// An upload that isn't attached to a memory yet can be cleaned up by the
    /// server, so reuse stays short.
    private let reuseWindow: TimeInterval = 5 * 60
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Memories"
    )
    #endif

    private struct Key: Hashable {
        let coupleID: UUID
        let content: Content
        let accessibilityText: String
    }

    private enum Content: Hashable {
        /// `occurrence` tells apart the same photo picked twice, which must become two
        /// uploads: the server refuses the same upload twice in one memory.
        case photo(Data, occurrence: Int)
        /// A video by its prepared file, which is new for every pick, so its bytes are
        /// never read to compare.
        case video(PreparedVideo)

        func hash(into hasher: inout Hasher) {
            switch self {
            case .photo(let data, let occurrence):
                hasher.combine(data)
                hasher.combine(occurrence)
            case .video(let video):
                hasher.combine(video.fileURL)
            }
        }
    }

    init(
        uploader: (any MemoryMediaUploading)?,
        imageCache: (any MemoryMediaImageCacheWriting)?,
        operationProvider: any SyncClientOperationProviding
    ) {
        self.uploader = uploader
        self.imageCache = imageCache
        self.operationProvider = operationProvider
    }

    var isAvailable: Bool {
        uploader != nil
    }

    /// Uploads each item in order and returns optimistic snapshots that already carry
    /// their backend `mediaAssetID`. Returns nil if any upload fails, so the caller can
    /// stop without attaching only some of them.
    func upload(
        _ media: [MemoryDraftMedia],
        coupleID: UUID,
        ownerUserID: UUID,
        startingSortOrder: Int,
        attachedMediaAssetIDs: Set<UUID> = []
    ) async -> [MemoryMediaSnapshot]? {
        guard !media.isEmpty else { return [] }
        guard let uploader else { return nil }
        defer { progress = nil }

        var snapshots: [MemoryMediaSnapshot] = []
        for (index, key) in keys(for: media, coupleID: coupleID).enumerated() {
            progress = MemoryMediaUploadProgress(current: index + 1, total: media.count)
            guard let result = await upload(key, using: uploader, attachedMediaAssetIDs: attachedMediaAssetIDs) else {
                return nil
            }
            let video = media[index].video
            snapshots.append(
                result.optimisticSnapshot(
                    ownerUserID: ownerUserID, kind: video == nil ? .image : .video, durationMs: video?.durationMs,
                    sortOrder: startingSortOrder + index, accessibilityText: key.accessibilityText
                )
            )
        }
        return snapshots
    }

    func reset() {
        uploaded = [:]
    }

    private func keys(for media: [MemoryDraftMedia], coupleID: UUID) -> [Key] {
        media.indices.map { index in
            let item = media[index]
            let content: Content = switch item.content {
            case .photo(let data):
                .photo(data, occurrence: media[..<index].count { $0.photoData == data })
            case .video(let video):
                .video(video)
            }
            return Key(coupleID: coupleID, content: content, accessibilityText: item.accessibilityText)
        }
    }

    private func upload(
        _ key: Key, using uploader: any MemoryMediaUploading, attachedMediaAssetIDs: Set<UUID>
    ) async -> MemoryMediaUploadResult? {
        if let reused = uploaded[key],
           attachedMediaAssetIDs.contains(reused.result.mediaAssetID)
            || Date().timeIntervalSince(reused.at) < reuseWindow {
            return reused.result
        }
        do {
            let result: MemoryMediaUploadResult
            switch key.content {
            case .photo(let photo, _):
                guard let compressed = await Self.compress(photo) else { return nil }
                result = try await upload(
                    MemoryUploadMedia(
                        data: compressed.data,
                        purpose: .photo,
                        mimeType: compressed.mediaType,
                        fileExtension: compressed.fileExtension,
                        width: compressed.width,
                        height: compressed.height,
                        accessibilityText: key.accessibilityText
                    ),
                    key, using: uploader
                )
                await imageCache?.cacheImageData(compressed.data, for: result.mediaAssetID)
            case .video(let video):
                // Read before the upload, so a purge while it runs keeps the video out of the cache.
                let videoCache = VideoFileCache.shared
                let videoGeneration = await videoCache?.privacyGeneration ?? 0
                result = try await upload(
                    MemoryUploadMedia(video: video, purpose: .photo, accessibilityText: key.accessibilityText),
                    key, using: uploader
                )
                // The sender plays their own copy instead of downloading it again.
                await videoCache?.store(video.fileURL, for: result.mediaAssetID, privacyGeneration: videoGeneration)
            }
            uploaded[key] = (result, Date())
            return result
        } catch {
            #if DEBUG
            logger.error("Uploading memory media failed: \(String(describing: error))")
            #endif
            return nil
        }
    }

    private func upload(
        _ media: MemoryUploadMedia, _ key: Key, using uploader: any MemoryMediaUploading
    ) async throws -> MemoryMediaUploadResult {
        try await uploader.uploadMedia(
            media,
            memoryMediaID: UUID(),
            coupleID: key.coupleID,
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
