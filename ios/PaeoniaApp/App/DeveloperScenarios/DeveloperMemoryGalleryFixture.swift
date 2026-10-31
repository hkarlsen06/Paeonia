#if DEBUG
import Foundation

enum DeveloperMemoryGalleryFixture {
    nonisolated static let firstPhotoID = UUID(uuidString: "e1000001-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let secondPhotoID = UUID(uuidString: "e1000002-0000-4000-8000-000000000002") ?? UUID()

    static func records() -> [MemoryRecord] {
        var records = DeveloperScenarioFixture.memoryRecords()
        guard let first = records.first else { return records }
        let original = first.snapshot
        let media = [
            MemoryMediaSnapshot(
                memoryMediaID: firstPhotoID, mediaAssetID: firstPhotoID,
                ownerUserID: DeveloperScenarioFixture.currentUserID, sortOrder: 1,
                updatedAt: original.updatedAt,
                accessibilityText: "Oslo Opera House beside the water in evening sunlight."
            ),
            MemoryMediaSnapshot(
                memoryMediaID: secondPhotoID, mediaAssetID: secondPhotoID,
                ownerUserID: DeveloperScenarioFixture.partnerUserID, sortOrder: 2,
                updatedAt: original.updatedAt,
                accessibilityText: "Three coffee cups, a camera and a sketchbook on a café table."
            )
        ]
        records[0].snapshot = MemorySnapshot(
            ownerUserID: original.ownerUserID, memoryID: original.memoryID, coupleID: original.coupleID,
            title: original.title, memoryDate: original.memoryDate, place: original.place,
            createdByUserID: original.createdByUserID, lastEditedByUserID: original.lastEditedByUserID,
            revision: original.revision, moderationStatus: original.moderationStatus,
            deletedAt: original.deletedAt, createdAt: original.createdAt, updatedAt: original.updatedAt,
            syncUpdatedAt: original.syncUpdatedAt, ownNote: original.ownNote, partnerNote: original.partnerNote,
            visibleMemoryMediaIDs: media.map(\.memoryMediaID), visibleMediaAssetIDs: media.map(\.mediaAssetID),
            media: media, threadID: original.threadID
        )
        return records
    }
}

/// The gallery exercises the real loaders and viewer without requesting private
/// media or requiring a connection. These photos are already bundled fixtures.
actor DeveloperMemoryGalleryImageProvider: MemoryMediaImageProviding {
    private let failsFirstFullImageLoad: Bool
    private var requestCounts: [UUID: Int] = [:]

    init(failsFirstFullImageLoad: Bool = false) {
        self.failsFirstFullImageLoad = failsFirstFullImageLoad
    }

    // swiftlint:disable:next async_without_await
    func imageData(for mediaAssetID: UUID?) async -> Data? {
        guard let mediaAssetID else { return nil }
        requestCounts[mediaAssetID, default: 0] += 1
        // The carousel receives the thumbnail first. Fail only its first
        // full-image request, so retry still uses the production gallery path.
        if failsFirstFullImageLoad, mediaAssetID == DeveloperMemoryGalleryFixture.firstPhotoID,
           requestCounts[mediaAssetID] == 2 { return nil }
        let name: String
        switch mediaAssetID {
        case DeveloperMemoryGalleryFixture.firstPhotoID: name = "oslo-opera"
        case DeveloperMemoryGalleryFixture.secondPhotoID: name = "oslo-cafe"
        default: return nil
        }
        return Bundle.main.url(forResource: "scenario-memory-\(name)", withExtension: "jpg")
            .flatMap { try? Data(contentsOf: $0) }
    }
}
#endif
