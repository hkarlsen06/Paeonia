import Foundation

nonisolated protocol DailyAnswerMediaImageProviding: Sendable {
    /// Returns the bytes for a revealed answer's media asset, fetching and caching a
    /// signed download the first time and serving from the local cache thereafter.
    func imageData(for mediaAssetID: UUID?) async -> Data?
}

nonisolated protocol DailyAnswerMediaImageCacheWriting: Sendable {
    /// Saves bytes this phone just uploaded, so showing them never downloads them again.
    func cacheImageData(_ data: Data, for mediaAssetID: UUID) async
}

nonisolated protocol DailyAnswerMediaCacheClearing: Sendable {
    /// Removes every cached reveal file. Used by the privacy cleanup when the user
    /// signs out, deletes their account, or loses access to the relationship.
    func clearAll() async
}

/// Fetches and caches revealed daily-answer media. Mirrors the profile photo image
/// service: check the on-disk cache first, otherwise resolve a signed URL through
/// `get_media_signed_url`, download, and cache by media asset id.
actor DailyAnswerMediaImageService: DailyAnswerMediaImageProviding, DailyAnswerMediaCacheClearing,
    DailyAnswerMediaImageCacheWriting {
    nonisolated static let shared: DailyAnswerMediaImageService? = try? live()

    private let client: PaeoniaConvexClient
    private let directoryURL: URL
    private let expiresInSeconds = 3_600
    private var inFlightDownloads: [UUID: Task<Data?, Never>] = [:]
    private var misses = MediaMissLog()

    init(
        client: PaeoniaConvexClient,
        directoryURL: URL = DailyAnswerMediaImageService.defaultDirectoryURL()
    ) {
        self.client = client
        self.directoryURL = directoryURL
    }

    nonisolated static func live() throws -> DailyAnswerMediaImageService {
        DailyAnswerMediaImageService(client: try PaeoniaConvexClientProvider.shared.client())
    }

    func imageData(for mediaAssetID: UUID?) async -> Data? {
        guard let mediaAssetID else {
            return nil
        }

        if let cached = try? Data(contentsOf: fileURL(for: mediaAssetID)) {
            if !MediaDownloadCheck.isWebPage(cached, mimeType: nil) {
                return cached
            }
            // A file that is a web page (for example a captive-portal page)
            // would otherwise stay cached under this asset ID for good.
            try? FileManager.default.removeItem(at: fileURL(for: mediaAssetID))
        }

        if misses.isRecentMiss(mediaAssetID) {
            return nil
        }

        if let inFlightDownload = inFlightDownloads[mediaAssetID] {
            return await inFlightDownload.value
        }

        let download = Task { await fetchAndCache(mediaAssetID: mediaAssetID) }
        inFlightDownloads[mediaAssetID] = download
        let data = await download.value
        // A privacy purge may have cleared the map and a newer download started since.
        if inFlightDownloads[mediaAssetID] == download {
            inFlightDownloads[mediaAssetID] = nil
        }
        return data
    }

    func cacheImageData(_ data: Data, for mediaAssetID: UUID) {
        store(data, for: mediaAssetID)
    }

    func clearAll() {
        PaeoniaImageMemoryCache.removeAll()
        misses.removeAll()
        inFlightDownloads.values.forEach { $0.cancel() }
        inFlightDownloads.removeAll()

        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func fetchAndCache(mediaAssetID: UUID) async -> Data? {
        let signedURL: URL?
        do {
            signedURL = try await signedURL(for: mediaAssetID)
        } catch {
            if MediaMissLog.isLasting(error) { misses.record(mediaAssetID) }
            return nil
        }
        // No URL usually means the photo's row is not visible to this phone yet. It may be a moment
        // away, so it is not remembered as a miss and a tap on the photo tries again.
        guard let signedURL else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: signedURL)
            guard !Task.isCancelled else {
                return nil
            }

            if let statusCode = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(statusCode) {
                if MediaMissLog.isLasting(statusCode: statusCode) { misses.record(mediaAssetID) }
                return nil
            }

            // A sign-in page from a captive portal answers 200 too, and would otherwise
            // become a permanent broken photo or voice note.
            guard !MediaDownloadCheck.isWebPage(data, mimeType: response.mimeType) else {
                misses.record(mediaAssetID)
                return nil
            }

            store(data, for: mediaAssetID)
            return data
        } catch {
            return nil
        }
    }

    private func signedURL(for mediaAssetID: UUID) async throws -> URL? {
        try await client.signedMediaURL(for: mediaAssetID, expiresInSeconds: expiresInSeconds)
    }

    private func store(_ data: Data, for mediaAssetID: UUID) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: mediaAssetID), options: [.atomic])
    }

    private func fileURL(for mediaAssetID: UUID) -> URL {
        directoryURL.appendingPathComponent(mediaAssetID.uuidString.lowercased(), isDirectory: false)
    }

    /// In Caches, so the private files are not backed up and the system can reclaim
    /// the space. Anything removed is downloaded again when it's next shown.
    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyAnswerMedia", isDirectory: true)
    }
}
