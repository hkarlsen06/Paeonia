import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

/// Saves that overlap, retries after a failed upload, slow reads, and the partner
/// changing or deleting a memory while this person works on it.
@MainActor
struct MemoriesViewModelRaceTests {
    @Test func aSecondSaveWhileTheFirstIsUploadingIsRefused() async throws {
        let uploader = MemoryTestMediaUploader(delay: .milliseconds(200))
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let photo = makeImageData()

        let first = Task {
            await env.viewModel.createMemory(title: "Beach", date: "2026-06-30", note: "", photos: [photo])
        }
        await waitUntil { env.viewModel.isSaving }
        let second = await env.viewModel.createMemory(title: "Beach", date: "2026-06-30", note: "", photos: [photo])

        #expect(!second)
        #expect(await first.value)
        #expect(env.viewModel.timeline.flatMap(\.memories).count == 1)
        #expect(await uploader.uploadCount == 1)
    }

    @Test func retryingAfterAFailedUploadReusesPhotosAlreadySent() async throws {
        let uploader = MemoryTestMediaUploader(failingCalls: [2])
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let photos = [makeImageData(color: .systemPink), makeImageData(color: .systemBlue)]

        let failed = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "", photos: photos)
        let saved = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "", photos: photos)

        #expect(!failed)
        #expect(saved)
        // The first photo went up once; only the second is sent again.
        #expect(await uploader.uploadCount == 3)
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(record.snapshot.visibleMediaAssetIDs.count == 2)
    }

    @Test func theSamePhotoPickedTwiceIsUploadedTwice() async throws {
        let uploader = MemoryTestMediaUploader()
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let photo = makeImageData()

        let saved = await env.viewModel.createMemory(
            title: "Twice",
            date: "2026-06-30",
            note: "",
            photos: [photo, photo]
        )

        #expect(saved)
        // The server refuses the same upload twice in one memory, so each pick needs its own.
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(Set(record.snapshot.visibleMediaAssetIDs).count == 2)
        #expect(await uploader.uploadCount == 2)
    }

    @Test func editingTheNoteKeepsATitleThePartnerChangedMeanwhile() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "First", photos: [])
        let openedWith = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        try await env.memoryStore.saveRemote(
            [.fixture(
                ownerUserID: env.userID,
                memoryID: openedWith.snapshot.memoryID,
                coupleID: env.coupleID,
                title: "Partner's title",
                revision: 2,
                ownNoteRevision: 1,
                syncUpdatedAt: Date(timeIntervalSince1970: 500)
            )],
            ownerUserID: env.userID,
            mergePolicy: .overwriteLocalChanges
        )
        await env.viewModel.load()

        let saved = await env.viewModel.saveEdits(MemoryEdit(
            base: openedWith,
            title: "Trip",
            date: "2026-06-30",
            note: "Second thoughts",
            newPhotos: [],
            removedMedia: []
        ))

        #expect(saved)
        let updated = try #require(env.viewModel.record(for: openedWith.snapshot.memoryID))
        #expect(updated.snapshot.title == "Partner's title")
        #expect(updated.snapshot.ownNote?.body == "Second thoughts")
        let titleWrites = try await env.pendingStore.inFlightOperations(ownerUserID: env.userID, kind: .updateMemory)
        #expect(titleWrites.isEmpty)
    }

    @Test func aSlowReadCannotPutOlderMemoriesBackOnScreen() async throws {
        let service = GatedMemoryDataService(
            base: MemoryDataService(
                memoryStore: InMemoryMemoryRecordRepository(),
                pendingOperationStore: InMemoryPendingSyncOperationRepository()
            )
        )
        let viewModel = MemoriesViewModel(
            memoryService: service,
            operationProvider: MemoryTestOperationProvider(),
            mediaUploader: nil,
            mediaImageCache: nil,
            draftStore: makeIsolatedMemoryDraftStore()
        )
        await viewModel.configure(currentUserID: UUID(), coupleID: UUID())

        await service.holdNextLoad()
        let staleLoad = Task { await viewModel.load() }
        await service.waitUntilHolding()
        _ = await viewModel.createMemory(title: "New", date: "2026-06-30", note: "Note", photos: [])
        #expect(viewModel.timeline.flatMap(\.memories).count == 1)

        await service.release()
        await staleLoad.value

        #expect(viewModel.timeline.flatMap(\.memories).count == 1)
    }

    @Test func deletingAMemoryThePartnerAlreadyDeletedIsQuiet() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "Note", photos: [])
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        try await env.memoryStore.saveRemote(
            [.fixture(
                ownerUserID: env.userID,
                memoryID: record.snapshot.memoryID,
                coupleID: env.coupleID,
                title: "Trip",
                revision: 2,
                deletedAt: Date(timeIntervalSince1970: 600),
                syncUpdatedAt: Date(timeIntervalSince1970: 600)
            )],
            ownerUserID: env.userID,
            mergePolicy: .overwriteLocalChanges
        )

        await env.viewModel.deleteMemory(record)

        #expect(env.viewModel.notice == nil)
        #expect(env.viewModel.timeline.isEmpty)
        let deletes = try await env.pendingStore.inFlightOperations(ownerUserID: env.userID, kind: .hideMemory)
        #expect(deletes.isEmpty)
    }

    @Test func addingPhotosToAMemoryThePartnerDeletedQueuesNothing() async throws {
        let uploader = MemoryTestMediaUploader()
        let env = makeEnvironment(uploader: uploader)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "Note", photos: [])
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        try await env.memoryStore.saveRemote(
            [.fixture(
                ownerUserID: env.userID,
                memoryID: record.snapshot.memoryID,
                coupleID: env.coupleID,
                title: "Trip",
                revision: 2,
                deletedAt: Date(timeIntervalSince1970: 600),
                syncUpdatedAt: Date(timeIntervalSince1970: 600)
            )],
            ownerUserID: env.userID,
            mergePolicy: .overwriteLocalChanges
        )

        let saved = await env.viewModel.saveEdits(MemoryEdit(
            base: record,
            title: "Trip",
            date: "2026-06-30",
            note: "Note",
            newPhotos: [makeImageData()],
            removedMedia: []
        ))

        #expect(!saved)
        #expect(env.viewModel.notice == .memoryRemoved)
        let attaches = try await env.pendingStore.inFlightOperations(ownerUserID: env.userID, kind: .attachMemoryMedia)
        #expect(attaches.isEmpty)
        #expect(await uploader.uploadCount == 0)
    }

    @Test func savingAPhotoToTheLibraryReportsTheOutcome() async throws {
        let saver = MemoryTestPhotoSaver(result: .permissionDenied)
        let env = makeEnvironment(imageProvider: MemoryTestImageProvider(), photoSaver: saver)
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)

        await env.viewModel.savePhotoToLibrary(mediaAssetID: UUID())
        #expect(env.viewModel.notice == .photoSaveDenied)

        saver.result = .saved
        await env.viewModel.savePhotoToLibrary(mediaAssetID: UUID())
        #expect(env.viewModel.notice == .photoSaved)
    }

    // MARK: - Environment

    private func makeEnvironment(
        uploader: (any MemoryMediaUploading)? = nil,
        imageProvider: (any MemoryMediaImageProviding)? = nil,
        photoSaver: any PhotoLibrarySaving = MemoryTestPhotoSaver(result: .saved),
        draftStore: (any MemoryDraftStoring)? = nil
    ) -> MemoriesTestEnvironment {
        makeMemoriesTestEnvironment(
            uploader: uploader,
            imageProvider: imageProvider,
            photoSaver: photoSaver,
            draftStore: draftStore
        )
    }

    private func makeImageData(color: UIColor = .systemPink) -> Data {
        makeMemoryTestImageData(color: color)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        await waitForMemoryTestCondition(condition)
    }
}
