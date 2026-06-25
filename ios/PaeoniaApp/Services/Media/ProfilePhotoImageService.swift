import Foundation

protocol ProfilePhotoImageCaching: Sendable {
    func profilePhotoData(for mediaAssetID: UUID) async -> Data?
    func storeProfilePhotoData(_ data: Data, for mediaAssetID: UUID) async throws
    func removeProfilePhotoData(for mediaAssetID: UUID) async throws
    func removeAllProfilePhotoData() async throws
}

protocol ProfilePhotoImageProviding: Sendable {
    func profilePhotoData(for mediaAssetID: UUID?) async -> Data?
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

final class ProfilePhotoImageService: @unchecked Sendable, ProfilePhotoImageProviding {
    private let cache: any ProfilePhotoImageCaching
    private let urlProvider: any ProfilePhotoURLProviding

    nonisolated init(
        cache: any ProfilePhotoImageCaching = FileProfilePhotoImageCache.live(),
        urlProvider: any ProfilePhotoURLProviding
    ) {
        self.cache = cache
        self.urlProvider = urlProvider
    }

    nonisolated static func live() throws -> ProfilePhotoImageService {
        try ProfilePhotoImageService(urlProvider: SupabaseProfilePhotoURLService.live())
    }

    func profilePhotoData(for mediaAssetID: UUID?) async -> Data? {
        guard let mediaAssetID else {
            return nil
        }

        if let cachedData = await cache.profilePhotoData(for: mediaAssetID) {
            return cachedData
        }

        guard let signedURL = try? await urlProvider.signedProfilePhotoURL(for: mediaAssetID) else {
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

            try? await cache.storeProfilePhotoData(data, for: mediaAssetID)
            return data
        } catch {
            return nil
        }
    }
}
