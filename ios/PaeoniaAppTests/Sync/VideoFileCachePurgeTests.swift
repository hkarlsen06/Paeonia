import Foundation
import Testing
@testable import PaeoniaApp

/// The privacy purge empties the video cache, and a video this phone sent while the purge
/// ran stays out of it.
struct VideoFileCachePurgeTests {
    @Test func aSentVideoStoredAfterAPurgeIsNotKept() async throws {
        try await withCache { cache, directory, sent in
            let generation = await cache.privacyGeneration
            await cache.clearAll()

            await cache.store(sent, for: UUID(), privacyGeneration: generation)

            #expect(Self.files(in: directory).isEmpty)
        }
    }

    @Test func aPurgeRemovesAStoredVideo() async throws {
        try await withCache { cache, directory, sent in
            await cache.store(sent, for: UUID(), privacyGeneration: await cache.privacyGeneration)
            try #require(Self.files(in: directory).count == 1)

            await cache.clearAll()

            #expect(Self.files(in: directory).isEmpty)
        }
    }

    private func withCache(
        _ body: (VideoFileCache, URL, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoFileCachePurgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sent = root.appendingPathComponent("sent.mp4")
        try Data("private video".utf8).write(to: sent)
        let client = PaeoniaConvexClient(
            deploymentURL: try #require(URL(string: "https://video-cache.paeonia.test")),
            session: URLSession(configuration: .ephemeral),
            tokenProvider: { "token" }
        )
        let directory = root.appendingPathComponent("Videos", isDirectory: true)
        try await body(VideoFileCache(client: client, directoryURL: directory), directory, sent)
    }

    private static func files(in directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }
}
