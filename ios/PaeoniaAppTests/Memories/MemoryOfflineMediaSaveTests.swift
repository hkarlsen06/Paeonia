import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

/// A memory with photos or a video saves on this phone without a connection, and its queued
/// create uploads them before the memory, under the ids the saved memory already shows.
@MainActor
struct MemoryOfflineMediaSaveTests {
    @Test func photosSavedWithoutAConnectionShowAtOnceAndUploadWhenTheMemoryIsSent() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let photos = [makeMemoryTestImageData(color: .systemPink), makeMemoryTestImageData(color: .systemBlue)]

        let saved = await env.viewModel.createMemory(
            title: "F", date: "2026-11-17", note: "", media: MemoryDraftMedia.photos(photos)
        )

        #expect(saved)
        #expect(env.viewModel.notice == nil)
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        let assetIDs = record.snapshot.visibleMediaAssetIDs
        #expect(assetIDs.count == 2)
        #expect(await env.imageCache.cachedMediaAssetIDs == assetIDs)

        // The connection drops after the first photo, so the memory waits for the next try.
        let uploader = MemoryTestMediaUploader(failingCalls: [2])
        let gateway = ScriptedMemoryGateway(rows: [])
        let operation = try await queuedCreate(in: env)
        await #expect(throws: MediaUploadError.self) {
            try await send(operation, in: env, uploader: uploader, gateway: gateway)
        }
        #expect(await gateway.creates.isEmpty)
        #expect(try await send(operation, in: env, uploader: uploader, gateway: gateway) == .succeeded)

        let created = try #require(await gateway.creates.first)
        #expect(created.mediaAssetIDs == assetIDs)
        let calls = await uploader.calls
        #expect(calls.map(\.mediaAssetID) == [assetIDs[0], assetIDs[1], assetIDs[0], assetIDs[1]])
        // The retry replays the same reservations, so the server sends back the same uploads.
        #expect(calls[2].reserveOperationID == calls[0].reserveOperationID)
        #expect(calls[3].reserveOperationID == calls[1].reserveOperationID)
    }

    @Test func aQueuedVideoKeepsItsFileUntilTheMemoryIsSent() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let directory = MemoryDraftMedia.videoDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([7, 7]).write(to: fileURL)
        let video = PreparedVideo(fileURL: fileURL, width: 720, height: 1_280, durationMs: 4_000, byteSize: 2)

        let saved = await env.viewModel.createMemory(
            title: "Trip", date: "2026-06-30", note: "", media: [MemoryDraftMedia(content: .video(video))]
        )

        #expect(saved)
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(record.snapshot.visibleMedia.map(\.kind) == [.video])
        #expect(record.snapshot.visibleMedia.first?.durationMs == 4_000)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let uploader = MemoryTestMediaUploader()
        let operation = try await queuedCreate(in: env)
        let handler = handler(env, uploader: uploader, gateway: ScriptedMemoryGateway(rows: []))
        #expect(try await handler.send(operation, context: context(env)) == .succeeded)
        #expect(await uploader.calls.map(\.mimeType) == [MediaUpload.videoMimeType])
        #expect(await uploader.calls.map(\.mediaAssetID) == record.snapshot.visibleMediaAssetIDs)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        await handler.didRecordSuccess(of: operation)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Environment

    private func makeEnvironment() -> MemoriesTestEnvironment {
        makeMemoriesTestEnvironment(
            imageProvider: nil, photoSaver: MemoryTestPhotoSaver(result: .saved), draftStore: nil
        )
    }

    private func queuedCreate(in env: MemoriesTestEnvironment) async throws -> PendingSyncOperationSnapshot {
        try #require(try await env.pendingStore.inFlightOperations(ownerUserID: env.userID, kind: .createMemory).first)
    }

    private func handler(
        _ env: MemoriesTestEnvironment, uploader: MemoryTestMediaUploader, gateway: ScriptedMemoryGateway
    ) -> CreateMemoryPendingOperationHandler {
        CreateMemoryPendingOperationHandler(gateway: gateway, memoryStore: env.memoryStore, uploader: uploader)
    }

    private func send(
        _ operation: PendingSyncOperationSnapshot,
        in env: MemoriesTestEnvironment,
        uploader: MemoryTestMediaUploader,
        gateway: ScriptedMemoryGateway
    ) async throws -> PendingSyncOperationSendResult {
        try await handler(env, uploader: uploader, gateway: gateway).send(operation, context: context(env))
    }

    private func context(_ env: MemoriesTestEnvironment) -> SyncContext {
        SyncContext(
            session: SyncSession(userID: env.userID),
            reason: .localChange,
            pendingOperationStore: env.pendingStore
        )
    }
}
