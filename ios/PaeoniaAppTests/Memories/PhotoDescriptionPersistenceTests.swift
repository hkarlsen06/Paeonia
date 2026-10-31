import Foundation
import Testing
@testable import PaeoniaApp

struct PhotoDescriptionPersistenceTests {
    @Test func descriptionEditsSurviveTheLocalStoreAndOutbox() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataMemoryRecordRepository(container: store.container)
        let pending = InMemoryPendingSyncOperationRepository()
        let service = MemoryDataService(memoryStore: repository, pendingOperationStore: pending)
        let owner = UUID()
        let assetID = UUID()
        let original = MemoryMediaSnapshot(
            memoryMediaID: UUID(), mediaAssetID: assetID, ownerUserID: owner,
            sortOrder: 0, updatedAt: Date(), accessibilityText: "Two mugs"
        )
        let created = try await service.createMemory(
            ownerUserID: owner, coupleID: UUID(), memoryID: UUID(), title: "Lake",
            memoryDate: "2026-10-01", noteBody: "A quiet morning", optimisticMedia: [original],
            place: nil, operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
        )
        let description = MemoryPhotoDescription(mediaAssetID: assetID, text: "Two red mugs beside the lake")
        _ = try await service.updateMemory(
            ownerUserID: owner, memoryID: created.snapshot.memoryID,
            expectedRevision: created.snapshot.revision, title: "Lake", memoryDate: "2026-10-01",
            photoDescriptions: [description],
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
        )
        let reopened = SwiftDataMemoryRecordRepository(container: store.container)
        let loaded = try await reopened.load(ownerUserID: owner, memoryID: created.snapshot.memoryID)
        #expect(loaded?.snapshot.media.first?.accessibilityText == description.text)
        #expect(loaded?.snapshot.ownNote?.body == "A quiet morning")
        let operations = try await pending.inFlightOperations(ownerUserID: owner, kind: .updateMemory)
        let data = try #require(operations.first?.requestData)
        let payload = try JSONDecoder().decode(UpdateMemoryOperationPayload.self, from: data)
        #expect(payload.photoDescriptions == [description])
    }

    @Test func storiesKeepDescriptionSeparateFromCaptionAfterReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let story = Story(
            id: UUID(), authorUserID: owner, mediaAssetID: UUID(), caption: "Morning",
            accessibilityText: "Sunlight on two mugs", createdAt: Date()
        )
        await FileStoriesCache(directoryURL: directory).save(StoriesSnapshot(stories: [story]), ownerUserID: owner)
        let restored = await FileStoriesCache(directoryURL: directory).snapshot(ownerUserID: owner)
        #expect(restored.stories.first?.accessibilityText == "Sunlight on two mugs")
        #expect(restored.stories.first?.caption == "Morning")
        let other = await FileStoriesCache(directoryURL: directory).snapshot(ownerUserID: UUID())
        #expect(other.stories.isEmpty)
    }
}
