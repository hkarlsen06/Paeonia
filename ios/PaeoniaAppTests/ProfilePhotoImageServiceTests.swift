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
}

private actor FakeProfilePhotoURLProvider: ProfilePhotoURLProviding {
    private(set) var requestedMediaAssetIDs: [UUID?] = []
    private let waitsForRelease: Bool
    private var isReleased = false

    init(waitsForRelease: Bool = false) {
        self.waitsForRelease = waitsForRelease
    }

    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL? {
        requestedMediaAssetIDs.append(mediaAssetID)
        while waitsForRelease && !isReleased {
            await Task.yield()
        }
        return nil
    }

    func release() {
        isReleased = true
    }
}
