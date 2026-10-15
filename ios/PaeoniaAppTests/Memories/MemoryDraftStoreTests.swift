import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct MemoryDraftStoreTests {
    private let userID = UUID()

    @Test func savesAndRestoresTextDateAndPhotos() {
        let store = makeIsolatedMemoryDraftStore()
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let photos = [Data([1, 2, 3]), Data([4, 5])]

        let draftPhotos = photos.map { MemoryDraftPhoto(data: $0) }

        store.setDraft(MemoryDraft(title: "Lake", date: date, note: "Cold", photos: draftPhotos), for: userID)

        let restored = store.draft(for: userID)
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

        LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
            .setDraft(MemoryDraft(title: "Lake", photos: [MemoryDraftPhoto(data: Data([9]))]), for: userID)

        let restored = LocalMemoryDraftStore(defaults: defaults, directoryURL: directory).draft(for: userID)
        #expect(restored?.title == "Lake")
        #expect(restored?.photos.map(\.data) == [Data([9])])
    }

    @Test func clearRemovesTextAndPhotoFiles() {
        let store = makeIsolatedMemoryDraftStore()
        store.setDraft(MemoryDraft(title: "Lake", photos: [MemoryDraftPhoto(data: Data([1]))]), for: userID)

        store.clearDraft(for: userID)

        #expect(store.draft(for: userID) == nil)
    }

    @Test func savingAnEmptyDraftRemovesTheStoredOne() {
        let store = makeIsolatedMemoryDraftStore()
        store.setDraft(MemoryDraft(title: "Lake"), for: userID)

        store.setDraft(MemoryDraft(title: "  ", note: ""), for: userID)

        #expect(store.draft(for: userID) == nil)
    }

    @Test func draftsAreIsolatedPerUser() {
        let store = makeIsolatedMemoryDraftStore()
        let otherUser = UUID()
        store.setDraft(MemoryDraft(title: "Mine", photos: [MemoryDraftPhoto(data: Data([1]))]), for: userID)
        store.setDraft(MemoryDraft(title: "Theirs"), for: otherUser)

        store.clearDraft(for: userID)

        #expect(store.draft(for: userID) == nil)
        #expect(store.draft(for: otherUser)?.title == "Theirs")
    }

    @Test func removingAPhotoShrinksTheStoredPhotos() {
        let store = makeIsolatedMemoryDraftStore()
        let first = MemoryDraftPhoto(data: Data([1]))
        let second = MemoryDraftPhoto(data: Data([2]))
        store.setDraft(MemoryDraft(title: "Lake", photos: [first, second]), for: userID)

        store.setDraft(MemoryDraft(title: "Lake", photos: [second]), for: userID)

        #expect(store.draft(for: userID)?.photos.map(\.data) == [Data([2])])
    }

    @Test func photosCompareByIDNotBytes() {
        let photo = MemoryDraftPhoto(data: Data([1]))
        #expect(photo == MemoryDraftPhoto(id: photo.id, data: Data([2])))
        #expect(photo != MemoryDraftPhoto(data: Data([1])))
    }

    @Test func copyableTextJoinsTitleAndNoteAndSkipsBlanks() {
        #expect(MemoryDraft(title: " Lake ", note: "Cold").copyableText == "Lake\n\nCold")
        #expect(MemoryDraft(title: "", note: "Cold").copyableText == "Cold")
        #expect(MemoryDraft(title: "  ", note: "").copyableText.isEmpty)
    }
}
