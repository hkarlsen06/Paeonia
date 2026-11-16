import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct MemoryVideoUploadTests {
    @Test func retryingReusesAVideoAlreadySentAndDeletesItsFileOnceSaved() async throws {
        let uploader = MemoryTestMediaUploader(failingCalls: [2])
        let env = makeMemoriesTestEnvironment(
            uploader: uploader, imageProvider: nil, photoSaver: MemoryTestPhotoSaver(result: .saved), draftStore: nil
        )
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([7, 7]).write(to: fileURL)
        let video = PreparedVideo(fileURL: fileURL, width: 720, height: 1_280, durationMs: 4_000, byteSize: 2)
        let media = [MemoryDraftMedia(content: .video(video))]
            + MemoryDraftMedia.photos([makeMemoryTestImageData(color: .systemPink)])

        let failed = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "", media: media)
        #expect(!failed)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let saved = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "", media: media)

        #expect(saved)
        // The video went up once; only the photo is sent again.
        #expect(await uploader.uploadCount == 3)
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(record.snapshot.visibleMedia.map(\.kind) == [.video, .image])
        #expect(record.snapshot.visibleMedia.first?.durationMs == 4_000)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
