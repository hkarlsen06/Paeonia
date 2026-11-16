import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct MemoryDraftStoreTests {
    private let userID = UUID()

    @Test func savesAndRestoresTextDateAndPhotos() throws {
        let store = makeIsolatedMemoryDraftStore()
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let photos = [Data([1, 2, 3]), Data([4, 5])]

        let draftPhotos = photos.map { MemoryDraftMedia(content: .photo($0)) }

        try store.setDraft(MemoryDraft(title: "Lake", date: date, note: "Cold", media: draftPhotos), for: userID)

        let restored = try store.draft(for: userID)
        #expect(restored?.title == "Lake")
        #expect(restored?.note == "Cold")
        #expect(restored?.date == date)
        #expect(restored?.media.compactMap(\.photoData) == photos)
    }

    @Test func restoresAfterTheStoreIsRecreated() throws {
        let name = "MemoryDraftTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }

        try LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
            .setDraft(
                MemoryDraft(title: "Lake", media: [
                    MemoryDraftMedia(content: .photo(Data([9])), accessibilityText: "Two mugs beside the lake")
                ]), for: userID
            )

        let restored = try LocalMemoryDraftStore(defaults: defaults, directoryURL: directory).draft(for: userID)
        #expect(restored?.title == "Lake")
        #expect(restored?.media.compactMap(\.photoData) == [Data([9])])
        #expect(restored?.media.first?.accessibilityText == "Two mugs beside the lake")
    }

    @Test func savingAnEmptyDraftRemovesTheStoredOne() throws {
        let store = makeIsolatedMemoryDraftStore()
        try store.setDraft(MemoryDraft(title: "Lake"), for: userID)

        try store.setDraft(MemoryDraft(title: "  ", note: ""), for: userID)

        #expect(try store.draft(for: userID) == nil)
    }

    @Test func draftsAreIsolatedPerUser() throws {
        let store = makeIsolatedMemoryDraftStore()
        let otherUser = UUID()
        try store.setDraft(MemoryDraft(title: "Mine", media: MemoryDraftMedia.photos([Data([1])])), for: userID)
        try store.setDraft(MemoryDraft(title: "Theirs"), for: otherUser)

        store.clearDraft(for: userID)

        #expect(try store.draft(for: userID) == nil)
        #expect(try store.draft(for: otherUser)?.title == "Theirs")
    }

    @Test func failedPhotoWriteLeavesThePreviouslySavedDraftIntact() throws {
        let name = "MemoryDraftTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let blockedDirectory = directory.appendingPathExtension("blocked")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: blockedDirectory)
        }
        let store = LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
        let original = MemoryDraft(title: "Saved", media: [MemoryDraftMedia(content: .photo(Data([1])))])
        try store.setDraft(original, for: userID)
        try Data([0]).write(to: blockedDirectory)
        let failingStore = LocalMemoryDraftStore(defaults: defaults, directoryURL: blockedDirectory)
        let changed = MemoryDraft(title: "Changed", media: [MemoryDraftMedia(content: .photo(Data([2])))])

        #expect(throws: (any Error).self) { try failingStore.setDraft(changed, for: userID) }

        let restored = try store.draft(for: userID)
        #expect(restored?.title == original.title)
        #expect(restored?.media.compactMap(\.photoData) == original.media.compactMap(\.photoData))
        try store.setDraft(changed, for: userID)
        #expect(try store.draft(for: userID)?.media.compactMap(\.photoData) == changed.media.compactMap(\.photoData))
    }

    @Test func unreadableAttachmentReportsFailureInsteadOfRestoringAnIncompleteDraft() throws {
        let name = "MemoryDraftTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
        try store.setDraft(MemoryDraft(title: "Trip", media: [
            MemoryDraftMedia(content: .photo(Data([1]))), MemoryDraftMedia(content: .photo(Data([2])))
        ]), for: userID)
        let attachment = directory.appendingPathComponent(userID.uuidString.lowercased()).appendingPathComponent("0")
        try FileManager.default.removeItem(at: attachment)

        #expect(throws: (any Error).self) { try store.draft(for: userID) }
        // Repairing the failed OS read recovers the whole existing draft.
        try Data([1]).write(to: attachment)
        let restored = try store.draft(for: userID)
        #expect(restored?.title == "Trip")
        #expect(restored?.media.compactMap(\.photoData) == [Data([1]), Data([2])])
    }

    @Test func restoresAPickedVideoByItsFileAndFailsWhenTheFileIsGone() throws {
        let store = makeIsolatedMemoryDraftStore()
        let directory = MemoryDraftMedia.videoDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([7, 7]).write(to: fileURL)
        let video = PreparedVideo(fileURL: fileURL, width: 720, height: 1_280, durationMs: 4_000, byteSize: 2)

        try store.setDraft(MemoryDraft(title: "Lake", media: [
            MemoryDraftMedia(content: .photo(Data([1]))),
            MemoryDraftMedia(content: .video(video), accessibilityText: "Jumping off the pier")
        ]), for: userID)

        let restored = try #require(try store.draft(for: userID))
        #expect(restored.media.map(\.photoData) == [Data([1]), nil])
        #expect(restored.media.last?.video == video)
        #expect(restored.media.last?.accessibilityText == "Jumping off the pier")

        try FileManager.default.removeItem(at: fileURL)
        #expect(throws: (any Error).self) { try store.draft(for: userID) }
    }
}
