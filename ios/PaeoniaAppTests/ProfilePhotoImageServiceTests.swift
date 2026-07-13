import Foundation
import Testing
@testable import PaeoniaApp

struct ProfilePhotoImageServiceTests {
    @Test func profilePhotoDataReturnsCachedDataWithoutRequestingSignedURL() async throws {
        let mediaAssetID = try #require(UUID(uuidString: "89B38D31-B105-42E0-AAB1-3766028D3487"))
        let cachedData = Data([0x01, 0x02, 0x03])
        let cache = FakeProfilePhotoCache(seed: [mediaAssetID: cachedData])
        let urlProvider = FakeProfilePhotoURLProvider()
        let service = ProfilePhotoImageService(
            cache: cache,
            urlProvider: urlProvider
        )

        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == cachedData)
        #expect(await urlProvider.requestedMediaAssetIDs.isEmpty)
    }

    @Test func overlappingRequestsForSamePhotoShareSignedURLLookup() async throws {
        let mediaAssetID = try #require(UUID(uuidString: "89B38D31-B105-42E0-AAB1-3766028D3487"))
        let cache = FakeProfilePhotoCache()
        let urlProvider = FakeProfilePhotoURLProvider(waitsForRelease: true)
        let service = ProfilePhotoImageService(
            cache: cache,
            urlProvider: urlProvider
        )

        async let first = service.profilePhotoData(for: mediaAssetID)
        while await urlProvider.requestedMediaAssetIDs.isEmpty {
            await Task.yield()
        }

        async let second = service.profilePhotoData(for: mediaAssetID)
        await Task.yield()

        #expect(await urlProvider.requestedMediaAssetIDs == [mediaAssetID])

        await urlProvider.release()
        let (firstData, secondData) = await (first, second)

        #expect(firstData == nil)
        #expect(secondData == nil)
        #expect(await urlProvider.requestedMediaAssetIDs == [mediaAssetID])
    }

    @Test func invalidatingPhotoRemovesCachedBytesAndBlocksTheRetiredAssetID() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache(seed: [mediaAssetID: Data([0x01])])
        let urlProvider = FakeProfilePhotoURLProvider(
            signedURL: try #require(URL(string: "https://example.com/profile.jpg"))
        )
        let service = ProfilePhotoImageService(cache: cache, urlProvider: urlProvider)

        await service.invalidate(mediaAssetID: mediaAssetID)
        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == nil)
        #expect(await cache.storedData(for: mediaAssetID) == nil)
        #expect(await urlProvider.requestedMediaAssetIDs.isEmpty)
    }

    @Test func invalidatingDuringDownloadPreventsStaleBytesFromBeingRewritten() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache()
        let downloader = SuspendingProfilePhotoDownloader(data: Data([0x01, 0x02]))
        let urlProvider = FakeProfilePhotoURLProvider(
            signedURL: try #require(URL(string: "https://example.com/profile.jpg"))
        )
        let service = ProfilePhotoImageService(
            cache: cache,
            urlProvider: urlProvider,
            downloader: downloader
        )

        let load = Task { await service.profilePhotoData(for: mediaAssetID) }
        await downloader.waitUntilStarted()
        let invalidation = Task { await service.invalidate(mediaAssetID: mediaAssetID) }
        await Task.yield()
        await downloader.release()

        await invalidation.value
        #expect(await load.value == nil)
        #expect(await cache.storedData(for: mediaAssetID) == nil)
    }
}

private actor FakeProfilePhotoCache: ProfilePhotoImageCaching {
    private var storedData: [UUID: Data]

    init(seed: [UUID: Data] = [:]) {
        self.storedData = seed
    }

    func profilePhotoData(for mediaAssetID: UUID) async -> Data? {
        storedData[mediaAssetID]
    }

    func storeProfilePhotoData(_ data: Data, for mediaAssetID: UUID) async throws {
        storedData[mediaAssetID] = data
    }

    func removeProfilePhotoData(for mediaAssetID: UUID) async throws {
        storedData[mediaAssetID] = nil
    }

    func removeAllProfilePhotoData() async throws {
        storedData.removeAll()
    }

    func storedData(for mediaAssetID: UUID) -> Data? {
        storedData[mediaAssetID]
    }
}

private actor FakeProfilePhotoURLProvider: ProfilePhotoURLProviding {
    private(set) var requestedMediaAssetIDs: [UUID?] = []
    private let waitsForRelease: Bool
    private let signedURL: URL?
    private var isReleased = false

    init(waitsForRelease: Bool = false, signedURL: URL? = nil) {
        self.waitsForRelease = waitsForRelease
        self.signedURL = signedURL
    }

    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL? {
        requestedMediaAssetIDs.append(mediaAssetID)
        while waitsForRelease && !isReleased {
            await Task.yield()
        }
        return signedURL
    }

    func release() {
        isReleased = true
    }
}

private actor SuspendingProfilePhotoDownloader: ProfilePhotoDataDownloading {
    private let data: Data
    private var continuation: CheckedContinuation<ProfilePhotoDownload, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    init(data: Data) {
        self.data = data
    }

    func download(from _: URL) async throws -> ProfilePhotoDownload {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            didStart = true
            let waiters = startedWaiters
            startedWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilStarted() async {
        guard !didStart else {
            return
        }

        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func release() {
        continuation?.resume(
            returning: ProfilePhotoDownload(data: data, statusCode: 200)
        )
        continuation = nil
    }
}
