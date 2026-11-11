import Foundation
import Testing
@testable import PaeoniaApp

/// A delete by either partner reaches this phone as a changed row. The photo it took away
/// leaves this phone's cache then, not at sign-out, unless something still shows it.
struct DeletedMediaEvictionTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeletedMediaEvictionTests-\(UUID().uuidString)", isDirectory: true)

    enum MemoryChange: CaseIterable {
        case memoryDeleted
        case photoRemoved
    }

    @Test(arguments: MemoryChange.allCases)
    func aMemoryPhotoLeavesTheCacheWhenItsMemoryStopsShowingIt(change: MemoryChange) async throws {
        let (owner, couple, memory, other) = (UUID(), UUID(), UUID(), UUID())
        let (removed, shared, kept) = (UUID(), UUID(), UUID())
        let photos = try await MemoryPhotos(directory: directory, cached: [removed, shared, kept])
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataMemoryRecordRepository(container: localStore.container, mediaCache: photos.service)
        let before = Date(timeIntervalSince1970: 100)
        try await repository.saveRemote([
            .fixture(ownerUserID: owner, memoryID: memory, coupleID: couple, title: "Harbour",
                     memoryMediaIDs: [removed, shared], syncUpdatedAt: before),
            .fixture(ownerUserID: owner, memoryID: other, coupleID: couple, title: "Ferry",
                     memoryMediaIDs: [shared, kept], syncUpdatedAt: before)
        ], ownerUserID: owner, mergePolicy: .preserveLocalChanges)

        let after = Date(timeIntervalSince1970: 200)
        let changed: MemoryRemoteRow = switch change {
        case .memoryDeleted:
            .fixture(ownerUserID: owner, memoryID: memory, coupleID: couple, title: "Harbour", revision: 2,
                     deletedAt: after, memoryMediaIDs: [removed, shared], syncUpdatedAt: after)
        case .photoRemoved:
            .fixture(ownerUserID: owner, memoryID: memory, coupleID: couple, title: "Harbour", revision: 2,
                     memoryMediaIDs: [shared], syncUpdatedAt: after)
        }
        try await repository.saveRemote([changed], ownerUserID: owner, mergePolicy: .preserveLocalChanges)

        #expect(await photos.isCached(removed) == false)
        #expect(await photos.isCached(shared), "the other memory still shows it")
        #expect(await photos.isCached(kept))
    }

    @Test func aDeletedStoryPhotoLeavesTheCache() async throws {
        let owner = UUID()
        let (deleted, kept) = (UUID(), UUID())
        let photos = try await MemoryPhotos(directory: directory, cached: [deleted, kept])
        let stories = FileStoriesCache(
            directoryURL: directory.appendingPathComponent("Stories", isDirectory: true),
            mediaCache: photos.service
        )
        let deletedStory = Story(id: UUID(), authorUserID: UUID(), mediaAssetID: deleted, caption: nil,
                                 createdAt: .now, seenAt: nil)
        let keptStory = Story(id: UUID(), authorUserID: UUID(), mediaAssetID: kept, caption: nil,
                              createdAt: .now, seenAt: nil)
        await stories.save(StoriesSnapshot(stories: [deletedStory, keptStory]), ownerUserID: owner)

        await stories.save(StoriesSnapshot(stories: [keptStory]), ownerUserID: owner)

        #expect(await photos.isCached(deleted) == false)
        #expect(await photos.isCached(kept))
    }

    @Test func thePartnersReplacedProfilePhotoLeavesTheCache() async throws {
        let owner = UUID()
        let (oldPhoto, newPhoto) = (UUID(), UUID())
        let diskCache = FileProfilePhotoImageCache(directoryURL: directory)
        try await diskCache.storeProfilePhotoData(Data("old".utf8), for: oldPhoto)
        try await diskCache.storeProfilePhotoData(Data("new".utf8), for: newPhoto)
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataAccessSyncSnapshotRepository(
            container: localStore.container,
            profilePhotoCache: ProfilePhotoImageService(cache: diskCache, urlProvider: NoProfilePhotoURLs())
        )
        let couple = UUID()
        try await repository.save(snapshot(owner: owner, couple: couple, partnerPhoto: oldPhoto))

        try await repository.save(snapshot(owner: owner, couple: couple, partnerPhoto: newPhoto))

        #expect(await diskCache.profilePhotoData(for: oldPhoto) == nil)
        #expect(await diskCache.profilePhotoData(for: newPhoto) != nil)
    }

    private func snapshot(owner: UUID, couple: UUID, partnerPhoto: UUID) -> AccessSyncSnapshot {
        AccessSyncSnapshot(
            ownerUserID: owner,
            userEntitlement: nil,
            coupleEntitlement: nil,
            relationshipState: RemoteRelationshipState(
                coupleID: couple, pairID: couple, relationshipStatus: .active, memberStatus: .active,
                acceptedInvite: false, partnerUserID: UUID(), partnerAccountName: "Panci",
                partnerProfilePhotoAssetID: partnerPhoto, startedOn: "2026-06-24",
                endedAt: nil, deleteAfter: nil, endedNoticeSeenAt: nil
            )
        )
    }
}

struct MemoryPhotos {
    let service: MemoryMediaImageService
    private let diskCache: MemoryMediaImageDiskCache

    init(directory: URL, cached: [UUID]) async throws {
        let mediaDirectory = directory.appendingPathComponent("MemoryMedia", isDirectory: true)
        diskCache = MemoryMediaImageDiskCache(directoryURL: mediaDirectory)
        service = MemoryMediaImageService(
            client: PaeoniaConvexClient(
                deploymentURL: try #require(URL(string: "https://deleted-media.invalid")),
                tokenProvider: { nil }
            ),
            directoryURL: mediaDirectory
        )
        for mediaAssetID in cached {
            await diskCache.store(Data("photo".utf8), for: mediaAssetID)
        }
    }

    func isCached(_ mediaAssetID: UUID) async -> Bool {
        await diskCache.imageData(for: mediaAssetID) != nil
    }
}

struct NoProfilePhotoURLs: ProfilePhotoURLProviding {
    // swiftlint:disable:next async_without_await
    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL? { nil }
}
