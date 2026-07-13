import Foundation

nonisolated protocol ProfilePhotoImageCaching: Sendable {
    func profilePhotoData(for mediaAssetID: UUID) async -> Data?
    func storeProfilePhotoData(_ data: Data, for mediaAssetID: UUID) async throws
    func removeProfilePhotoData(for mediaAssetID: UUID) async throws
    func removeAllProfilePhotoData() async throws
}

nonisolated protocol ProfilePhotoImageProviding: Sendable {
    func profilePhotoData(for mediaAssetID: UUID?) async -> Data?
}

nonisolated protocol ProfilePhotoImageCacheClearing: Sendable {
    func clearAll() async
}

nonisolated protocol ProfilePhotoImageInvalidating: Sendable {
    func invalidate(mediaAssetID: UUID) async
}

nonisolated struct ProfilePhotoDownload: Sendable {
    let data: Data
    let statusCode: Int?
}

nonisolated protocol ProfilePhotoDataDownloading: Sendable {
    func download(from url: URL) async throws -> ProfilePhotoDownload
}

nonisolated struct URLSessionProfilePhotoDataDownloader: ProfilePhotoDataDownloading {
    func download(from url: URL) async throws -> ProfilePhotoDownload {
        let (data, response) = try await URLSession.shared.data(from: url)
        return ProfilePhotoDownload(
            data: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode
        )
    }
}

nonisolated enum ProfilePhotoImageProviderFactory {
    static let shared: (any ProfilePhotoImageProviding)? = ProfilePhotoImageService.shared
    static let cacheInvalidator: (any ProfilePhotoImageInvalidating)? = ProfilePhotoImageService.shared
}

final class FileProfilePhotoImageCache: @unchecked Sendable, ProfilePhotoImageCaching {
    private let directoryURL: URL

    nonisolated init(
        directoryURL: URL = FileProfilePhotoImageCache.defaultDirectoryURL()
    ) {
        self.directoryURL = directoryURL
    }

    nonisolated static func live() -> FileProfilePhotoImageCache {
        FileProfilePhotoImageCache()
    }

    func profilePhotoData(for mediaAssetID: UUID) async -> Data? {
        try? Data(contentsOf: fileURL(for: mediaAssetID))
    }

    func storeProfilePhotoData(_ data: Data, for mediaAssetID: UUID) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL(for: mediaAssetID), options: [.atomic])
    }

    func removeProfilePhotoData(for mediaAssetID: UUID) async throws {
        let fileURL = fileURL(for: mediaAssetID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    func removeAllProfilePhotoData() async throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: directoryURL)
    }

    private func fileURL(for mediaAssetID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(mediaAssetID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("jpg")
    }

    nonisolated private static func defaultDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("ProfilePhotos", isDirectory: true)
    }
}

actor ProfilePhotoImageService:
    ProfilePhotoImageProviding,
    ProfilePhotoImageCacheClearing,
    ProfilePhotoImageInvalidating
{
    nonisolated static let shared: ProfilePhotoImageService? = try? live()

    private let cache: any ProfilePhotoImageCaching
    private let urlProvider: any ProfilePhotoURLProviding
    private let downloader: any ProfilePhotoDataDownloading
    private var inFlightDownloads: [UUID: Task<Data?, Never>] = [:]
    private var invalidatedMediaAssetIDs = Set<UUID>()
    private var privacyGeneration: UInt64 = 0

    init(
        cache: any ProfilePhotoImageCaching = FileProfilePhotoImageCache.live(),
        urlProvider: any ProfilePhotoURLProviding,
        downloader: any ProfilePhotoDataDownloading = URLSessionProfilePhotoDataDownloader()
    ) {
        self.cache = cache
        self.urlProvider = urlProvider
        self.downloader = downloader
    }

    nonisolated static func live() throws -> ProfilePhotoImageService {
        try ProfilePhotoImageService(urlProvider: SupabaseProfilePhotoURLService.live())
    }

    func profilePhotoData(for mediaAssetID: UUID?) async -> Data? {
        guard let mediaAssetID, !invalidatedMediaAssetIDs.contains(mediaAssetID) else {
            return nil
        }

        if let cachedData = await cache.profilePhotoData(for: mediaAssetID) {
            return cachedData
        }

        if let inFlightDownload = inFlightDownloads[mediaAssetID] {
            return await inFlightDownload.value
        }

        let requestedPrivacyGeneration = privacyGeneration
        let download = Task {
            await fetchAndCache(
                mediaAssetID: mediaAssetID,
                privacyGeneration: requestedPrivacyGeneration
            )
        }
        inFlightDownloads[mediaAssetID] = download
        let data = await download.value
        inFlightDownloads[mediaAssetID] = nil
        return data
    }

    func clearAll() async {
        privacyGeneration &+= 1
        let downloads = Array(inFlightDownloads.values)
        downloads.forEach { $0.cancel() }
        for download in downloads {
            _ = await download.value
        }
        inFlightDownloads.removeAll()
        try? await cache.removeAllProfilePhotoData()
    }

    func invalidate(mediaAssetID: UUID) async {
        invalidatedMediaAssetIDs.insert(mediaAssetID)
        if let download = inFlightDownloads.removeValue(forKey: mediaAssetID) {
            download.cancel()
            _ = await download.value
        }
        try? await cache.removeProfilePhotoData(for: mediaAssetID)
    }

    private func fetchAndCache(
        mediaAssetID: UUID,
        privacyGeneration requestedPrivacyGeneration: UInt64
    ) async -> Data? {
        guard let signedURL = try? await urlProvider.signedProfilePhotoURL(for: mediaAssetID) else {
            return nil
        }

        do {
            let download = try await downloader.download(from: signedURL)
            guard !Task.isCancelled,
                  requestedPrivacyGeneration == privacyGeneration,
                  !invalidatedMediaAssetIDs.contains(mediaAssetID)
            else {
                return nil
            }

            if let statusCode = download.statusCode,
               !(200..<300).contains(statusCode) {
                return nil
            }

            try? await cache.storeProfilePhotoData(download.data, for: mediaAssetID)
            guard !Task.isCancelled,
                  requestedPrivacyGeneration == privacyGeneration,
                  !invalidatedMediaAssetIDs.contains(mediaAssetID)
            else {
                try? await cache.removeProfilePhotoData(for: mediaAssetID)
                return nil
            }
            return download.data
        } catch {
            return nil
        }
    }
}
