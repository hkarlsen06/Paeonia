import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct MemoriesViewModelTests {
    @Test func createNoteOnlyMemoryShowsInTimelineAndQueuesWrite() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)

        let saved = await env.viewModel.createMemory(
            title: "  First trip  ",
            date: "2026-06-30",
            note: "  We made it.  ",
            photos: []
        )

        #expect(saved)
        let memories = env.viewModel.timeline.flatMap(\.memories)
        #expect(memories.count == 1)
        let record = try #require(memories.first)
        #expect(record.snapshot.title == "First trip")
        #expect(record.snapshot.ownNote?.body == "We made it.")
        #expect(record.syncStatus == .dirty)

        let queued = try await env.pendingStore.inFlightOperations(
            ownerUserID: env.userID,
            kind: .createMemory
        )
        #expect(queued.count == 1)
    }

    @Test func createMemoryWithPhotoUploadsAndAttachesMedia() async throws {
        let uploader = StubMemoryMediaUploader()
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)

        let saved = await env.viewModel.createMemory(
            title: "Beach day",
            date: "2026-06-30",
            note: "",
            photos: [makeImageData()]
        )

        #expect(saved)
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(record.snapshot.media.count == 1)
        #expect(record.snapshot.visibleMediaAssetIDs.count == 1)
        let uploadCount = await uploader.uploadCount
        #expect(uploadCount == 1)
        let cachedAssetIDs = await env.imageCache.cachedMediaAssetIDs
        #expect(cachedAssetIDs == record.snapshot.visibleMediaAssetIDs)
    }

    @Test func createMemoryFailsWhenPhotoUploadFails() async throws {
        let uploader = StubMemoryMediaUploader(shouldFail: true)
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)

        let saved = await env.viewModel.createMemory(
            title: "Beach day",
            date: "2026-06-30",
            note: "",
            photos: [makeImageData()]
        )

        #expect(!saved)
        #expect(env.viewModel.timeline.isEmpty)
        #expect(env.viewModel.notice == .photoUploadFailed)
    }

    @Test func createMemoryWithEmptyTitleIsRejectedWithoutNotice() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)

        let saved = await env.viewModel.createMemory(
            title: "   ",
            date: "2026-06-30",
            note: "Something",
            photos: []
        )

        #expect(!saved)
        #expect(env.viewModel.timeline.isEmpty)
        #expect(env.viewModel.notice == nil)
    }

    @Test func addPhotosCachesUploadedImageForImmediateDisplay() async throws {
        let uploader = StubMemoryMediaUploader()
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "First", photos: [])
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)

        let added = await env.viewModel.addPhotos(to: record, photos: [makeImageData()])

        #expect(added)
        let updated = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(updated.snapshot.media.count == 1)
        #expect(updated.snapshot.visibleMediaAssetIDs.count == 1)
        let cachedAssetIDs = await env.imageCache.cachedMediaAssetIDs
        #expect(cachedAssetIDs == updated.snapshot.visibleMediaAssetIDs)
    }

    @Test func deleteMemoryRemovesItFromTheTimeline() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "Note", photos: [])
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)

        await env.viewModel.deleteMemory(record)

        #expect(env.viewModel.timeline.isEmpty)
    }

    @Test func saveNoteUpdatesOwnNote() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "First", photos: [])
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)

        let saved = await env.viewModel.saveNote(for: record, body: "Updated note")

        #expect(saved)
        let updated = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(updated.snapshot.ownNote?.body == "Updated note")
    }

    @Test func configureFlushesLocalChangesThroughTheSyncHandler() async throws {
        let env = makeEnvironment()
        let counter = CallCounter()
        env.viewModel.setLocalChangeSyncHandler { counter.count += 1 }

        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        await waitUntil { counter.count >= 1 }

        #expect(counter.count >= 1)
    }

    @Test func observeStoreChangesShowsAPartnersMemoryAndRemovesItWhenHidden() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let observer = Task { await env.viewModel.observeStoreChanges() }
        let memoryID = UUID()
        func row(deletedAt: Date? = nil, revision: Int) -> MemoryRemoteRow {
            .fixture(
                ownerUserID: env.userID,
                memoryID: memoryID,
                coupleID: env.coupleID,
                title: "From my partner",
                revision: revision,
                deletedAt: deletedAt,
                syncUpdatedAt: Date(timeIntervalSince1970: 100)
            )
        }

        try await env.memoryStore.saveRemote([row(revision: 1)], ownerUserID: env.userID, mergePolicy: .preserveLocalChanges)
        await waitUntil { env.viewModel.record(for: memoryID) != nil }
        #expect(env.viewModel.record(for: memoryID)?.snapshot.title == "From my partner")

        try await env.memoryStore.saveRemote(
            [row(deletedAt: Date(timeIntervalSince1970: 200), revision: 2)],
            ownerUserID: env.userID,
            mergePolicy: .preserveLocalChanges
        )
        await waitUntil { env.viewModel.record(for: memoryID) == nil }
        #expect(env.viewModel.record(for: memoryID) == nil)
        observer.cancel()
    }

    @Test func observeStoreChangesIgnoresAnotherUsersWrites() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let observer = Task { await env.viewModel.observeStoreChanges() }
        let otherUserID = UUID()
        let memoryID = UUID()

        try await env.memoryStore.saveRemote(
            [.fixture(
                ownerUserID: otherUserID,
                memoryID: memoryID,
                coupleID: env.coupleID,
                title: "Not mine",
                syncUpdatedAt: Date(timeIntervalSince1970: 100)
            )],
            ownerUserID: otherUserID,
            mergePolicy: .preserveLocalChanges
        )
        try? await Task.sleep(for: .milliseconds(50))

        #expect(env.viewModel.timeline.isEmpty)
        observer.cancel()
    }

    // MARK: - New memory draft

    @Test func draftIsSavedPerUserAndRestoredWhenTheSessionReloads() async {
        let store = makeIsolatedMemoryDraftStore()
        let first = makeEnvironment(draftStore: store)
        await first.viewModel.configure(currentUserID: first.userID, coupleID: first.coupleID)
        first.viewModel.updateDraft(MemoryDraft(title: "Lake", note: "Cold water"))

        // A new view model stands in for the tab being torn down and rebuilt.
        let second = makeEnvironment(draftStore: store)
        #expect(second.viewModel.draft.isEmpty)
        await second.viewModel.configure(currentUserID: first.userID, coupleID: first.coupleID)

        #expect(second.viewModel.draft.title == "Lake")
        #expect(second.viewModel.draft.note == "Cold water")
    }

    @Test func draftDoesNotLeakToAnotherUser() async {
        let store = makeIsolatedMemoryDraftStore()
        let env = makeEnvironment(draftStore: store)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        env.viewModel.updateDraft(MemoryDraft(title: "Private", note: "Mine"))

        await env.viewModel.configure(currentUserID: UUID(), coupleID: env.coupleID)
        #expect(env.viewModel.draft.isEmpty)

        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        #expect(env.viewModel.draft.title == "Private")
    }

    @Test func savingTheMemoryClearsTheSavedDraft() async {
        let store = makeIsolatedMemoryDraftStore()
        let env = makeEnvironment(draftStore: store)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        env.viewModel.updateDraft(MemoryDraft(title: "Trip", note: "Great"))
        #expect(store.draft(for: env.userID) != nil)

        let saved = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "Great", photos: [])

        #expect(saved)
        #expect(env.viewModel.draft.isEmpty)
        #expect(store.draft(for: env.userID) == nil)
    }

    @Test func aFailedSaveKeepsTheSavedDraft() async {
        let store = makeIsolatedMemoryDraftStore()
        let env = makeEnvironment(
            uploader: StubMemoryMediaUploader(shouldFail: true),
            draftStore: store
        )
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        env.viewModel.updateDraft(MemoryDraft(title: "Trip", photos: [makeImageData()]))

        let saved = await env.viewModel.createMemory(
            title: "Trip",
            date: "2026-06-30",
            note: "",
            photos: [makeImageData()]
        )

        #expect(!saved)
        #expect(store.draft(for: env.userID)?.title == "Trip")
        #expect(store.draft(for: env.userID)?.photos.count == 1)
    }

    @Test func discardingTheDraftClearsTheSavedCopy() async {
        let store = makeIsolatedMemoryDraftStore()
        let env = makeEnvironment(draftStore: store)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        env.viewModel.updateDraft(MemoryDraft(title: "Trip", note: "Great"))

        env.viewModel.updateDraft(MemoryDraft())

        #expect(store.draft(for: env.userID) == nil)
    }

    // MARK: - Environment

    private struct Environment {
        let viewModel: MemoriesViewModel
        let pendingStore: InMemoryPendingSyncOperationRepository
        let memoryStore: InMemoryMemoryRecordRepository
        let imageCache: StubMemoryMediaImageCache
        let userID: UUID
        let coupleID: UUID
    }

    private func makeEnvironment(
        uploader: (any MemoryMediaUploading)? = nil,
        draftStore: (any MemoryDraftStoring)? = nil
    ) -> Environment {
        let memoryStore = InMemoryMemoryRecordRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: memoryStore, pendingOperationStore: pendingStore)
        let imageCache = StubMemoryMediaImageCache()
        let viewModel = MemoriesViewModel(
            memoryService: service,
            operationProvider: StubOperationProvider(),
            mediaUploader: uploader,
            mediaImageCache: imageCache,
            draftStore: draftStore ?? makeIsolatedMemoryDraftStore()
        )
        return Environment(
            viewModel: viewModel,
            pendingStore: pendingStore,
            memoryStore: memoryStore,
            imageCache: imageCache,
            userID: UUID(),
            coupleID: UUID()
        )
    }

    private func makeImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class CallCounter {
    var count = 0
}

@MainActor
private final class StubOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = UUID()

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(clientID: clientID, clientSequence: sequence)
    }
}

private actor StubMemoryMediaImageCache: MemoryMediaImageCacheWriting {
    private(set) var cachedMediaAssetIDs: [UUID] = []

    func cacheImageData(_ data: Data, for mediaAssetID: UUID) async {
        guard !data.isEmpty else { return }
        cachedMediaAssetIDs.append(mediaAssetID)
    }
}

private actor StubMemoryMediaUploader: MemoryMediaUploading {
    private let shouldFail: Bool
    private(set) var uploadCount = 0

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult {
        uploadCount += 1
        if shouldFail {
            throw MemoryMediaUploadError.finalizeFailed
        }
        return MemoryMediaUploadResult(memoryMediaID: memoryMediaID, mediaAssetID: UUID())
    }
}

/// A draft store backed by a throwaway defaults suite and temp directory, so tests never
/// touch the app's real drafts.
@MainActor
func makeIsolatedMemoryDraftStore() -> LocalMemoryDraftStore {
    let name = "MemoryDraftTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(name, isDirectory: true)
    return LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
}
