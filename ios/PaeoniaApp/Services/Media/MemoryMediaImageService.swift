import Foundation

nonisolated protocol MemoryMediaImageProviding: Sendable {
    /// Returns the bytes for a memory's photo asset, fetching and caching a signed
    /// download the first time and serving from the local cache thereafter.
    func imageData(for mediaAssetID: UUID?) async -> Data?
}

nonisolated protocol MemoryMediaImageCacheWriting: Sendable {
    /// Stores bytes for a media asset that was just uploaded by this device, so the UI
    /// can render it immediately without waiting for a signed download retry.
    func cacheImageData(_ data: Data, for mediaAssetID: UUID) async
}

nonisolated protocol MemoryMediaImageCacheClearing: Sendable {
    /// Removes every cached memory photo. Used by the privacy cleanup when the user
    /// signs out, deletes their account, or loses access to the relationship.
    func clearAll() async
}

actor MemoryMediaImageDiskCache: MemoryMediaImageCacheWriting {
    let directoryURL: URL

    init(directoryURL: URL = MemoryMediaImageDiskCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    func imageData(for mediaAssetID: UUID?) -> Data? {
        guard let mediaAssetID else {
            return nil
        }
        return try? Data(contentsOf: fileURL(for: mediaAssetID))
    }

    func cacheImageData(_ data: Data, for mediaAssetID: UUID) {
        store(data, for: mediaAssetID)
    }

    func store(_ data: Data, for mediaAssetID: UUID) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: mediaAssetID), options: [.atomic])
    }

    func remove(for mediaAssetID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: mediaAssetID))
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func fileURL(for mediaAssetID: UUID) -> URL {
        directoryURL.appendingPathComponent(mediaAssetID.uuidString.lowercased(), isDirectory: false)
    }

    /// In Caches, so the private photos are not backed up and the system can reclaim
    /// the space. Anything removed is downloaded again when it's next shown.
    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemoryMedia", isDirectory: true)
    }
}

/// Fetches and caches memory photos. Mirrors the daily-answer media service: check
/// the on-disk cache first, otherwise resolve a signed URL through
/// `get_media_signed_url`, download, and cache by media asset id. A separate cache
/// directory keeps memory photos isolated from daily-answer media.
actor MemoryMediaImageService: MemoryMediaImageProviding, MemoryMediaImageCacheClearing {
    nonisolated static let shared: MemoryMediaImageService? = try? live()

    private let client: PaeoniaConvexClient
    private let cache: MemoryMediaImageDiskCache
    private let expiresInSeconds = 3_600
    private var inFlightDownloads: [UUID: Task<Data?, Never>] = [:]
    private var misses = MediaMissLog()
    /// Bumped by every purge, so a download that started before it can tell and drop
    /// its photo instead of saving it.
    private var privacyGeneration: UInt64 = 0

    init(
        client: PaeoniaConvexClient,
        directoryURL: URL = MemoryMediaImageService.defaultDirectoryURL()
    ) {
        self.client = client
        self.cache = MemoryMediaImageDiskCache(directoryURL: directoryURL)
    }

    nonisolated static func live() throws -> MemoryMediaImageService {
        MemoryMediaImageService(client: try PaeoniaConvexClientProvider.shared.client())
    }

    func imageData(for mediaAssetID: UUID?) async -> Data? {
        guard let mediaAssetID else {
            return nil
        }

        if let cached = await cache.imageData(for: mediaAssetID) {
            if ProfilePhotoImageService.isDecodableImage(cached) {
                return cached
            }
            // A file that is not an image (for example a captive-portal page)
            // would otherwise stay cached under this asset ID for good.
            await cache.remove(for: mediaAssetID)
        }

        if misses.isRecentMiss(mediaAssetID) {
            return nil
        }

        if let inFlightDownload = inFlightDownloads[mediaAssetID] {
            return await inFlightDownload.value
        }

        let requestedPrivacyGeneration = privacyGeneration
        let download = Task {
            await fetchAndCache(mediaAssetID: mediaAssetID, privacyGeneration: requestedPrivacyGeneration)
        }
        inFlightDownloads[mediaAssetID] = download
        let data = await download.value
        // A purge may have cleared the map and a newer download started since.
        if inFlightDownloads[mediaAssetID] == download {
            inFlightDownloads[mediaAssetID] = nil
        }
        return data
    }

    func clearAll() async {
        privacyGeneration &+= 1
        misses.removeAll()
        let downloads = Array(inFlightDownloads.values)
        downloads.forEach { $0.cancel() }
        inFlightDownloads.removeAll()
        // A download that is saving its photo right now finishes first, and sees the
        // new generation, so nothing it wrote survives the delete below.
        for download in downloads {
            _ = await download.value
        }

        await cache.clearAll()
    }

    private func fetchAndCache(mediaAssetID: UUID, privacyGeneration requested: UInt64) async -> Data? {
        guard let data = await download(mediaAssetID: mediaAssetID, privacyGeneration: requested) else {
            return nil
        }

        await cache.store(data, for: mediaAssetID)
        guard !Task.isCancelled, requested == privacyGeneration else {
            await cache.remove(for: mediaAssetID)
            return nil
        }
        return data
    }

    /// The photo's bytes, or nil. Remembers a failure that retrying will not fix.
    private func download(mediaAssetID: UUID, privacyGeneration requested: UInt64) async -> Data? {
        let url: URL?
        do {
            url = try await signedURL(for: mediaAssetID)
        } catch {
            if MediaMissLog.isLasting(error) { misses.record(mediaAssetID) }
            return nil
        }
        // No URL usually means the photo's row is not visible to this phone yet. It may be a moment
        // away, so it is not remembered as a miss and a tap on the photo tries again.
        guard let url else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, requested == privacyGeneration else {
                return nil
            }

            if let statusCode = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(statusCode) {
                if MediaMissLog.isLasting(statusCode: statusCode) { misses.record(mediaAssetID) }
                return nil
            }

            // Only an image is worth keeping. A sign-in page from a captive portal
            // answers 200 too, and would otherwise become a permanent broken photo.
            guard ProfilePhotoImageService.isDecodableImage(data) else {
                misses.record(mediaAssetID)
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func signedURL(for mediaAssetID: UUID) async throws -> URL? {
        try await client.signedMediaURL(for: mediaAssetID, expiresInSeconds: expiresInSeconds)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        MemoryMediaImageDiskCache.defaultDirectoryURL()
    }
}
