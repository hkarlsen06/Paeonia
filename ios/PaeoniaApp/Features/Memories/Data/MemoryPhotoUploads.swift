import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// How far a save has got through uploading its photos, for the save button.
nonisolated struct MemoryPhotoUploadProgress: Equatable, Sendable {
    /// 1-based number of the photo being sent now.
    let current: Int
    let total: Int
}

/// Sends the photos of a memory save. Photos go one at a time, compressed off the main
/// actor. A photo that went up before a later one failed is reused when the person
/// tries again within a few minutes, instead of being sent twice.
@MainActor
@Observable
final class MemoryPhotoUploads {
    private(set) var progress: MemoryPhotoUploadProgress?

    private let uploader: (any MemoryMediaUploading)?
    private let imageCache: (any MemoryMediaImageCacheWriting)?
    private let operationProvider: any SyncClientOperationProviding
    private var uploaded: [Key: (result: MemoryMediaUploadResult, at: Date)] = [:]
    /// An uploaded photo that isn't attached to a memory yet can be cleaned up by the
    /// server, so reuse stays short.
    private let reuseWindow: TimeInterval = 5 * 60
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Memories"
    )
    #endif

    /// `occurrence` tells apart the same photo picked twice, which must become two
    /// uploads: the server refuses the same upload twice in one memory.
    private struct Key: Hashable {
        let coupleID: UUID
        let photo: Data
        let occurrence: Int
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

    /// Uploads each photo in order and returns optimistic snapshots that already carry
    /// their backend `mediaAssetID`. Returns nil if any photo fails, so the caller can
    /// stop without attaching only some of them.
    func upload(
        _ photos: [Data],
        coupleID: UUID,
        ownerUserID: UUID,
        startingSortOrder: Int
    ) async -> [MemoryMediaSnapshot]? {
        guard !photos.isEmpty else { return [] }
        guard let uploader else { return nil }
        defer { progress = nil }

        var snapshots: [MemoryMediaSnapshot] = []
        for (index, key) in keys(for: photos, coupleID: coupleID).enumerated() {
            progress = MemoryPhotoUploadProgress(current: index + 1, total: photos.count)
            guard let result = await upload(key, using: uploader) else {
                return nil
            }
            snapshots.append(
                result.optimisticSnapshot(ownerUserID: ownerUserID, sortOrder: startingSortOrder + index)
            )
        }
        return snapshots
    }

    /// Drops reusable uploads once their photos are attached to a memory.
    func forget(_ photos: [Data], coupleID: UUID) {
        for key in keys(for: photos, coupleID: coupleID) {
            uploaded[key] = nil
        }
    }

    func reset() {
        uploaded = [:]
    }

    private func keys(for photos: [Data], coupleID: UUID) -> [Key] {
        photos.indices.map { index in
            let photo = photos[index]
            let occurrence = photos[..<index].count(where: { $0 == photo })
            return Key(coupleID: coupleID, photo: photo, occurrence: occurrence)
        }
    }

    private func upload(_ key: Key, using uploader: any MemoryMediaUploading) async -> MemoryMediaUploadResult? {
        if let reused = uploaded[key], Date().timeIntervalSince(reused.at) < reuseWindow {
            return reused.result
        }
        guard let compressed = await Self.compress(key.photo) else { return nil }

        do {
            let result = try await uploader.uploadMedia(
                MemoryUploadMedia(
                    data: compressed.data,
                    purpose: .photo,
                    mimeType: compressed.mediaType,
                    fileExtension: compressed.fileExtension,
                    width: compressed.width,
                    height: compressed.height
                ),
                memoryMediaID: UUID(),
                coupleID: key.coupleID,
                reserveOperation: operationProvider.makeOperation(),
                finalizeOperation: operationProvider.makeOperation()
            )
            uploaded[key] = (result, Date())
            await imageCache?.cacheImageData(compressed.data, for: result.mediaAssetID)
            return result
        } catch {
            #if DEBUG
            logger.error("Uploading a memory photo failed: \(String(describing: error))")
            #endif
            return nil
        }
    }

    /// Compressing a full camera photo takes a noticeable moment, so it runs off the
    /// main actor and the save spinner keeps moving.
    @concurrent
    private nonisolated static func compress(_ photo: Data) async -> ImageCompressor.CompressedImage? {
        ImageCompressor.compress(photo)
    }
}
