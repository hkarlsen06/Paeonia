import Foundation
import Testing
@testable import PaeoniaApp

struct ProfilePhotoImageServiceTests {
    @Test func profilePhotoDataReturnsCachedDataWithoutRequestingSignedURL() async throws {
        let mediaAssetID = try #require(UUID(uuidString: "89B38D31-B105-42E0-AAB1-3766028D3487"))
        let cachedData = TestImage.png
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
        // The second call reads the cache before it joins the download. Releasing
        // the download before that read would end it, and the second call would
        // then rightly start its own.
        while await cache.reads < 2 {
            await Task.yield()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(await urlProvider.requestedMediaAssetIDs == [mediaAssetID])

        await urlProvider.release()
        let (firstData, secondData) = await (first, second)

        #expect(firstData == nil)
        #expect(secondData == nil)
        #expect(await urlProvider.requestedMediaAssetIDs == [mediaAssetID])
    }

    @Test func invalidatingPhotoRemovesCachedBytesAndBlocksTheRetiredAssetID() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache(seed: [mediaAssetID: TestImage.png])
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
        let downloader = SuspendingProfilePhotoDownloader(data: TestImage.png)
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
        // The service retires the asset ID before it cancels the download, so a
        // cancelled download means the invalidation is already recorded.
        #expect(await waitUntil { await downloader.wasCancelled })
        await downloader.release()

        await invalidation.value
        #expect(await load.value == nil)
        #expect(await cache.storedData(for: mediaAssetID) == nil)
    }

    @Test func validDownloadIsCachedAndReturned() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache()
        let downloader = StubProfilePhotoDownloader(data: TestImage.png)
        let service = try makeService(cache: cache, downloader: downloader)

        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == TestImage.png)
        #expect(await cache.storedData(for: mediaAssetID) == TestImage.png)
    }

    @Test func undecodableDownloadIsNotCachedAndReturnsNil() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache()
        let downloader = StubProfilePhotoDownloader(data: TestImage.captivePortalPage)
        let service = try makeService(cache: cache, downloader: downloader)

        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == nil)
        #expect(await cache.storedData(for: mediaAssetID) == nil)
        #expect(await downloader.downloadCount == 1)
    }

    @Test func failedStatusCodeIsNotCachedEvenWithImageBytes() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache()
        let downloader = StubProfilePhotoDownloader(data: TestImage.png, statusCode: 404)
        let service = try makeService(cache: cache, downloader: downloader)

        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == nil)
        #expect(await cache.storedData(for: mediaAssetID) == nil)
    }

    @Test func undecodableCachedFileIsTreatedAsAMissAndRefetched() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache(seed: [mediaAssetID: TestImage.captivePortalPage])
        let downloader = StubProfilePhotoDownloader(data: TestImage.png)
        let service = try makeService(cache: cache, downloader: downloader)

        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == TestImage.png)
        #expect(await cache.storedData(for: mediaAssetID) == TestImage.png)
        #expect(await downloader.downloadCount == 1)
    }

    @Test func undecodableCachedFileIsRemovedWhenTheRefetchFails() async throws {
        let mediaAssetID = UUID()
        let cache = FakeProfilePhotoCache(seed: [mediaAssetID: TestImage.captivePortalPage])
        let downloader = StubProfilePhotoDownloader(data: TestImage.captivePortalPage)
        let service = try makeService(cache: cache, downloader: downloader)

        let data = await service.profilePhotoData(for: mediaAssetID)

        #expect(data == nil)
        #expect(await cache.storedData(for: mediaAssetID) == nil)
    }

    private func makeService(
        cache: FakeProfilePhotoCache,
        downloader: any ProfilePhotoDataDownloading
    ) throws -> ProfilePhotoImageService {
        ProfilePhotoImageService(
            cache: cache,
            urlProvider: FakeProfilePhotoURLProvider(
                signedURL: try #require(URL(string: "https://example.com/profile.jpg"))
            ),
            downloader: downloader
        )
    }
}

private enum TestImage {
    /// A valid 1x1 PNG.
    static let png = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA"
            + "60e6kgAAAABJRU5ErkJggg=="
    ) ?? Data()

    static let captivePortalPage = Data("<html><body>Sign in to the Wi-Fi network</body></html>".utf8)
}

// Actors supply the async-ness, so the sync fake bodies need no await.
// swiftlint:disable async_without_await
private actor StubProfilePhotoDownloader: ProfilePhotoDataDownloading {
    private let result: ProfilePhotoDownload
    private(set) var downloadCount = 0

    init(data: Data, statusCode: Int? = 200) {
        result = ProfilePhotoDownload(data: data, statusCode: statusCode)
    }

    func download(from _: URL) async throws -> ProfilePhotoDownload {
        downloadCount += 1
        return result
    }
}

private actor FakeProfilePhotoCache: ProfilePhotoImageCaching {
    private var storedData: [UUID: Data]
    private(set) var reads = 0

    init(seed: [UUID: Data] = [:]) {
        self.storedData = seed
    }

    func profilePhotoData(for mediaAssetID: UUID) async -> Data? {
        reads += 1
        return storedData[mediaAssetID]
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
    private(set) var wasCancelled = false

    init(data: Data) {
        self.data = data
    }

    /// Records cancellation but keeps waiting, so the test decides when the
    /// bytes arrive.
    func download(from _: URL) async throws -> ProfilePhotoDownload {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                didStart = true
                let waiters = startedWaiters
                startedWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            Task { await self.markCancelled() }
        }
    }

    private func markCancelled() {
        wasCancelled = true
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
// swiftlint:enable async_without_await
