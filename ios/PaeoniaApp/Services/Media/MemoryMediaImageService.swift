import Foundation
import Supabase

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

    func cacheImageData(_ data: Data, for mediaAssetID: UUID) async {
        store(data, for: mediaAssetID)
    }

    func store(_ data: Data, for mediaAssetID: UUID) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: mediaAssetID), options: [.atomic])
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

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemoryMedia", isDirectory: true)
    }
}

/// Fetches and caches memory photos. Mirrors the daily-answer media service: check
/// the on-disk cache first, otherwise resolve a signed URL through
/// `get_media_signed_url`, download, and cache by media asset id. A separate cache
/// directory keeps memory photos isolated from daily-answer media.
actor MemoryMediaImageService: MemoryMediaImageProviding, MemoryMediaImageCacheClearing {
    private let client: SupabaseClient
    private let cache: MemoryMediaImageDiskCache
    private let expiresInSeconds = 3_600
    private var inFlightDownloads: [UUID: Task<Data?, Never>] = [:]

    init(
        client: SupabaseClient,
        directoryURL: URL = MemoryMediaImageService.defaultDirectoryURL()
    ) {
        self.client = client
        self.cache = MemoryMediaImageDiskCache(directoryURL: directoryURL)
    }

    nonisolated static func live() throws -> MemoryMediaImageService {
        MemoryMediaImageService(client: try PaeoniaSupabaseClientProvider.shared.client())
    }

    func imageData(for mediaAssetID: UUID?) async -> Data? {
        guard let mediaAssetID else {
            return nil
        }

        if let cached = await cache.imageData(for: mediaAssetID) {
            return cached
        }

        if let inFlightDownload = inFlightDownloads[mediaAssetID] {
            return await inFlightDownload.value
        }

        let download = Task { await fetchAndCache(mediaAssetID: mediaAssetID) }
        inFlightDownloads[mediaAssetID] = download
        let data = await download.value
        inFlightDownloads[mediaAssetID] = nil
        return data
    }

    func clearAll() async {
        inFlightDownloads.values.forEach { $0.cancel() }
        inFlightDownloads.removeAll()

        await cache.clearAll()
    }

    private func fetchAndCache(mediaAssetID: UUID) async -> Data? {
        guard let signedURL = try? await signedURL(for: mediaAssetID) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: signedURL)
            guard !Task.isCancelled else {
                return nil
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }

            await cache.store(data, for: mediaAssetID)
            return data
        } catch {
            return nil
        }
    }

    private func signedURL(for mediaAssetID: UUID) async throws -> URL? {
        let rows: [MemoryMediaSignedURLAuthorization] = try await client
            .rpc(
                "get_media_signed_url",
                params: MemoryMediaSignedURLRequest(
                    mediaAssetID: mediaAssetID,
                    expiresInSeconds: expiresInSeconds
                )
            )
            .execute()
            .value

        guard let authorization = rows.first else {
            return nil
        }

        return try await client.storage
            .from(authorization.bucket)
            .createSignedURL(
                path: authorization.storagePath,
                expiresIn: authorization.expiresInSeconds
            )
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        MemoryMediaImageDiskCache.defaultDirectoryURL()
    }
}

nonisolated private struct MemoryMediaSignedURLRequest: Encodable, Sendable {
    let mediaAssetID: UUID
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case expiresInSeconds = "p_expires_in_seconds"
    }
}

nonisolated private struct MemoryMediaSignedURLAuthorization: Decodable, Sendable {
    let mediaAssetID: UUID
    let bucket: String
    let storagePath: String
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case bucket
        case storagePath = "storage_path"
        case expiresInSeconds = "expires_in_seconds"
    }
}
