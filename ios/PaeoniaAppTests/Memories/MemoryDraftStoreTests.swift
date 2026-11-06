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

        let draftPhotos = photos.map { MemoryDraftPhoto(data: $0) }

        try store.setDraft(MemoryDraft(title: "Lake", date: date, note: "Cold", photos: draftPhotos), for: userID)

        let restored = try store.draft(for: userID)
        #expect(restored?.title == "Lake")
        #expect(restored?.note == "Cold")
        #expect(restored?.date == date)
        #expect(restored?.photos.map(\.data) == photos)
    }

    @Test func restoresAfterTheStoreIsRecreated() throws {
        let name = "MemoryDraftTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }

        try LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
            .setDraft(
                MemoryDraft(title: "Lake", photos: [
                    MemoryDraftPhoto(data: Data([9]), accessibilityText: "Two mugs beside the lake")
                ]), for: userID
            )

        let restored = try LocalMemoryDraftStore(defaults: defaults, directoryURL: directory).draft(for: userID)
        #expect(restored?.title == "Lake")
        #expect(restored?.photos.map(\.data) == [Data([9])])
        #expect(restored?.photos.first?.accessibilityText == "Two mugs beside the lake")
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
        try store.setDraft(MemoryDraft(title: "Mine", photos: [MemoryDraftPhoto(data: Data([1]))]), for: userID)
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
        let original = MemoryDraft(title: "Saved", photos: [MemoryDraftPhoto(data: Data([1]))])
        try store.setDraft(original, for: userID)
        try Data([0]).write(to: blockedDirectory)
        let failingStore = LocalMemoryDraftStore(defaults: defaults, directoryURL: blockedDirectory)
        let changed = MemoryDraft(title: "Changed", photos: [MemoryDraftPhoto(data: Data([2]))])

        #expect(throws: (any Error).self) { try failingStore.setDraft(changed, for: userID) }

        let restored = try store.draft(for: userID)
        #expect(restored?.title == original.title)
        #expect(restored?.photos.map(\.data) == original.photos.map(\.data))
        try store.setDraft(changed, for: userID)
        #expect(try store.draft(for: userID)?.photos.map(\.data) == changed.photos.map(\.data))
    }

    @Test func unreadableAttachmentReportsFailureInsteadOfRestoringAnIncompleteDraft() throws {
        let name = "MemoryDraftTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
        try store.setDraft(MemoryDraft(title: "Trip", photos: [
            MemoryDraftPhoto(data: Data([1])), MemoryDraftPhoto(data: Data([2]))
        ]), for: userID)
        let attachment = directory.appendingPathComponent(userID.uuidString.lowercased()).appendingPathComponent("0")
        try FileManager.default.removeItem(at: attachment)

        #expect(throws: (any Error).self) { try store.draft(for: userID) }
        // Repairing the failed OS read recovers the whole existing draft.
        try Data([1]).write(to: attachment)
        let restored = try store.draft(for: userID)
        #expect(restored?.title == "Trip")
        #expect(restored?.photos.map(\.data) == [Data([1]), Data([2])])
    }
}
