import Foundation
import Synchronization
import Testing
@testable import PaeoniaApp

/// The app can end at any moment while it evicts a deleted photo. The change that removed
/// the photo then arrives again after the restart, and must still evict it. And evicting
/// one photo must not spoil the other photos this phone is loading at the same time.
struct DeletedMediaEvictionOrderTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeletedMediaEvictionOrderTests-\(UUID().uuidString)", isDirectory: true)

    @Test func aMemoryPhotoStillLeavesWhenTheAppEndsDuringItsEviction() async throws {
        let (owner, couple, memory, photo) = (UUID(), UUID(), UUID(), UUID())
        let photos = try await MemoryPhotos(directory: directory, cached: [photo])
        let localStore = try PaeoniaLocalStore(inMemory: true)
        try await SwiftDataMemoryRecordRepository(container: localStore.container, mediaCache: nil).saveRemote(
            [.fixture(ownerUserID: owner, memoryID: memory, coupleID: couple, title: "Harbour",
                      memoryMediaIDs: [photo], syncUpdatedAt: Date(timeIntervalSince1970: 100))],
            ownerUserID: owner, mergePolicy: .preserveLocalChanges
        )
        let deleted: [MemoryRemoteRow] = [.fixture(
            ownerUserID: owner, memoryID: memory, coupleID: couple, title: "Harbour", revision: 2,
            deletedAt: Date(timeIntervalSince1970: 200), memoryMediaIDs: [photo],
            syncUpdatedAt: Date(timeIntervalSince1970: 200)
        )]

        let stalling = StallingEvictor()
        let interrupted = SwiftDataMemoryRecordRepository(container: localStore.container, mediaCache: stalling)
        let ended = Task {
            try await interrupted.saveRemote(deleted, ownerUserID: owner, mergePolicy: .preserveLocalChanges)
        }
        try await stalling.waitUntilStalled()

        let restarted = SwiftDataMemoryRecordRepository(container: localStore.container, mediaCache: photos.service)
        try await restarted.saveRemote(deleted, ownerUserID: owner, mergePolicy: .preserveLocalChanges)

        #expect(await photos.isCached(photo) == false)
        await stalling.release()
        _ = try? await ended.value
    }

    @Test func aStoryPhotoStillLeavesWhenTheAppEndsDuringItsEviction() async throws {
        let owner = UUID()
        let photo = UUID()
        let photos = try await MemoryPhotos(directory: directory, cached: [photo])
        let storiesURL = directory.appendingPathComponent("Stories", isDirectory: true)
        let story = Story(id: UUID(), authorUserID: UUID(), mediaAssetID: photo, caption: nil,
                          createdAt: .now, seenAt: nil)
        await FileStoriesCache(directoryURL: storiesURL, mediaCache: nil)
            .save(StoriesSnapshot(stories: [story]), ownerUserID: owner)

        let stalling = StallingEvictor()
        let interrupted = FileStoriesCache(directoryURL: storiesURL, mediaCache: stalling)
        let ended = Task { await interrupted.save(StoriesSnapshot(), ownerUserID: owner) }
        try await stalling.waitUntilStalled()

        await FileStoriesCache(directoryURL: storiesURL, mediaCache: photos.service)
            .save(StoriesSnapshot(), ownerUserID: owner)

        #expect(await photos.isCached(photo) == false)
        await stalling.release()
        await ended.value
    }

    @Test func thePartnersOldPhotoStillLeavesWhenTheAppEndsDuringItsEviction() async throws {
        let owner = UUID()
        let (oldPhoto, newPhoto) = (UUID(), UUID())
        let diskCache = FileProfilePhotoImageCache(directoryURL: directory)
        try await diskCache.storeProfilePhotoData(TestPNG.data, for: oldPhoto)
        let localStore = try PaeoniaLocalStore(inMemory: true)
        try await SwiftDataAccessSyncSnapshotRepository(container: localStore.container, profilePhotoCache: nil)
            .save(accessSnapshot(owner: owner, partnerPhoto: oldPhoto))

        let stalling = StallingEvictor()
        let interrupted = SwiftDataAccessSyncSnapshotRepository(
            container: localStore.container, profilePhotoCache: stalling
        )
        let ended = Task { try await interrupted.save(accessSnapshot(owner: owner, partnerPhoto: newPhoto)) }
        try await stalling.waitUntilStalled()

        let restarted = SwiftDataAccessSyncSnapshotRepository(
            container: localStore.container,
            profilePhotoCache: ProfilePhotoImageService(cache: diskCache, urlProvider: NoProfilePhotoURLs())
        )
        try await restarted.save(accessSnapshot(owner: owner, partnerPhoto: newPhoto))

        #expect(await diskCache.profilePhotoData(for: oldPhoto) == nil)
        await stalling.release()
        _ = try? await ended.value
    }

    @Test func evictingOnePhotoLetsAnotherPhotosDownloadFinish() async throws {
        let (evicted, loading) = (UUID(), UUID())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let photoFile = directory.appendingPathComponent("loading.png")
        try TestPNG.data.write(to: photoFile)
        let server = HeldSignedURLServer(signedURL: photoFile)
        let mediaDirectory = directory.appendingPathComponent("MemoryMedia", isDirectory: true)
        let service = MemoryMediaImageService(client: try server.client(), directoryURL: mediaDirectory)

        let download = Task { await service.imageData(for: loading) }
        try await server.waitForRequest()
        await service.evict(mediaAssetIDs: [evicted])
        server.answer()

        #expect(await download.value == TestPNG.data)
        #expect(await MemoryMediaImageDiskCache(directoryURL: mediaDirectory).imageData(for: loading) != nil)
    }

    @Test func aGuessedReplacementDoesNotKeepThePartnersCurrentPhotoAway() async throws {
        let owner = UUID()
        let (current, stale) = (UUID(), UUID())
        let service = ProfilePhotoImageService(
            cache: FileProfilePhotoImageCache(directoryURL: directory),
            urlProvider: FixedProfilePhotoURL(),
            downloader: PNGDownloader()
        )
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataAccessSyncSnapshotRepository(
            container: localStore.container, profilePhotoCache: service
        )
        try await repository.save(accessSnapshot(owner: owner, partnerPhoto: current))

        // An older whole snapshot, read before the partner's new photo arrived, is saved last.
        try await repository.save(accessSnapshot(owner: owner, partnerPhoto: stale))

        #expect(await service.profilePhotoData(for: current) == TestPNG.data)
    }

    private func accessSnapshot(owner: UUID, partnerPhoto: UUID) -> AccessSyncSnapshot {
        AccessSyncSnapshot(
            ownerUserID: owner,
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: RemoteRelationshipState(
                coupleID: owner, pairID: owner, relationshipStatus: .active, memberStatus: .active,
                acceptedInvite: false, partnerUserID: owner, partnerAccountName: "Panci",
                partnerProfilePhotoAssetID: partnerPhoto, startedOn: "2026-06-24",
                endedAt: nil, deleteAfter: nil, endedNoticeSeenAt: nil
            )
        )
    }
}

/// Stops inside `evict`, where the app ending would leave the eviction undone.
private actor StallingEvictor: MediaCacheEvicting {
    private var stalled: CheckedContinuation<Void, Never>?

    func evict(mediaAssetIDs: [UUID]) async {
        await withCheckedContinuation { stalled = $0 }
    }

    func waitUntilStalled() async throws {
        for _ in 0..<500 where stalled == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(stalled != nil, "the save never reached the eviction")
    }

    func release() {
        stalled?.resume()
        stalled = nil
    }
}

private enum TestPNG {
    /// A valid 1x1 PNG.
    static let data = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA"
            + "60e6kgAAAABJRU5ErkJggg=="
    ) ?? Data()
}

/// Answers `media:get_media_signed_url` with `signedURL` once the test lets it, so a
/// download can be held in its network call.
private final class HeldSignedURLServer: Sendable {
    private let host = "held-\(UUID().uuidString.lowercased()).invalid"

    init(signedURL: URL) {
        HeldSignedURLProtocol.state.withLock { $0[host] = .init(signedURL: signedURL) }
    }

    func client() throws -> PaeoniaConvexClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldSignedURLProtocol.self]
        return PaeoniaConvexClient(
            deploymentURL: try #require(URL(string: "https://\(host)")),
            session: URLSession(configuration: configuration),
            tokenProvider: { nil }
        )
    }

    func waitForRequest() async throws {
        for _ in 0..<500 where !HeldSignedURLProtocol.state.withLock({ $0[host]?.requested ?? false }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(HeldSignedURLProtocol.state.withLock { $0[host]?.requested ?? false })
    }

    func answer() {
        HeldSignedURLProtocol.state.withLock { $0[host]?.gate.signal() }
    }
}

// swiftlint:disable static_over_final_class
private final class HeldSignedURLProtocol: URLProtocol, @unchecked Sendable {
    struct Held {
        let signedURL: URL
        let gate = DispatchSemaphore(value: 0)
        var requested = false
    }

    static let state = Mutex<[String: Held]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let held = Self.state.withLock({ state -> Held? in
                  state[host]?.requested = true
                  return state[host]
              })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        _ = held.gate.wait(timeout: .now() + 10)
        let body = #"{"status":"success","value":[{"signed_url":"\#(held.signedURL.absoluteString)"}]}"#
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
// swiftlint:enable static_over_final_class

private struct FixedProfilePhotoURL: ProfilePhotoURLProviding {
    // swiftlint:disable:next async_without_await
    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL? {
        URL(string: "https://profile-photo.invalid/\(mediaAssetID?.uuidString ?? "")")
    }
}

private struct PNGDownloader: ProfilePhotoDataDownloading {
    // swiftlint:disable:next async_without_await
    func download(from url: URL) async throws -> ProfilePhotoDownload {
        ProfilePhotoDownload(data: TestPNG.data, statusCode: 200)
    }
}
