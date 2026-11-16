import Foundation
import Testing
@testable import PaeoniaApp

/// A picture that started loading before a privacy purge finishes after it, and must not
/// go back into the memory caches the purge emptied.
struct ImageMemoryCachePurgeTests {
    @Test func aChatPhotoDecodedAcrossAPurgeIsNotKept() async throws {
        let key = "chat-\(UUID().uuidString)"
        let generation = PaeoniaImageMemoryCache.generation
        PaeoniaImageMemoryCache.removeAll()

        let decoded = await ThreadChatAttachmentLayout.decodeAndCache(Self.png, key: key, generation: generation)

        try #require(decoded != nil)
        #expect(PaeoniaImageMemoryCache.image(forKey: key) == nil)
    }

    @Test func aMemoryPhotoDecodedAcrossAPurgeIsNotKept() async throws {
        let mediaAssetID = UUID()
        let generation = MemoryImageDecoding.generation
        MemoryImageDecoding.removeAll()
        let decoded = try #require(await MemoryImageDecoding.downsample(Self.png, maxPixelSize: 64))

        MemoryImageDecoding.store(decoded, for: mediaAssetID, maxPixelSize: 64, generation: generation)

        #expect(MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: 64) == nil)
    }

    /// A valid 1x1 PNG.
    private static let png = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA"
            + "60e6kgAAAABJRU5ErkJggg=="
    ) ?? Data()
}
