import Foundation
import Testing
@testable import PaeoniaApp

struct PartnerAvatarSharingServiceTests {
    @Test func partnerRemovingTheirPhotoRemovesTheStagedOne() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: container) }
        let fileURL = container.appendingPathComponent(PaeoniaAppGroup.communicationPartnerAvatarPath)
        let service = PartnerAvatarSharingService(
            imageProvider: StubPhotoProvider(data: Data([1, 2, 3])),
            appGroupContainerURL: container
        )

        #expect(await service.cachePartnerAvatar(assetID: UUID()))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        #expect(await service.cachePartnerAvatar(assetID: nil))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func downloadFinishingAfterTheRemovalDoesNotBringThePhotoBack() async {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: container) }
        let fileURL = container.appendingPathComponent(PaeoniaAppGroup.communicationPartnerAvatarPath)
        let provider = SuspendedPhotoProvider()
        let service = PartnerAvatarSharingService(imageProvider: provider, appGroupContainerURL: container)

        async let staging = service.cachePartnerAvatar(assetID: UUID())
        await provider.waitUntilRequested()
        await service.cachePartnerAvatar(assetID: nil)
        await provider.release(Data([1, 2, 3]))
        _ = await staging

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func failedDownloadReportsThatItCanBeTriedAgain() async {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = PartnerAvatarSharingService(
            imageProvider: StubPhotoProvider(data: nil),
            appGroupContainerURL: container
        )

        #expect(await service.cachePartnerAvatar(assetID: UUID()) == false)
    }
}

private struct StubPhotoProvider: ProfilePhotoImageProviding {
    let data: Data?

    func profilePhotoData(for _: UUID?) async -> Data? {
        await Task.yield()
        return data
    }
}

private actor SuspendedPhotoProvider: ProfilePhotoImageProviding {
    private var download: CheckedContinuation<Data?, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func profilePhotoData(for _: UUID?) async -> Data? {
        await withCheckedContinuation { continuation in
            download = continuation
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard download == nil else {
            return
        }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func release(_ data: Data?) {
        download?.resume(returning: data)
        download = nil
    }
}
