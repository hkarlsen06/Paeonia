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

    // MARK: - Environment

    private struct Environment {
        let viewModel: MemoriesViewModel
        let pendingStore: InMemoryPendingSyncOperationRepository
        let memoryStore: InMemoryMemoryRecordRepository
        let userID: UUID
        let coupleID: UUID
    }

    private func makeEnvironment(uploader: (any MemoryMediaUploading)? = nil) -> Environment {
        let memoryStore = InMemoryMemoryRecordRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: memoryStore, pendingOperationStore: pendingStore)
        let viewModel = MemoriesViewModel(
            memoryService: service,
            operationProvider: StubOperationProvider(),
            mediaUploader: uploader
        )
        return Environment(
            viewModel: viewModel,
            pendingStore: pendingStore,
            memoryStore: memoryStore,
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
