import Foundation

/// Local persistence for a half-written new memory, so it survives the Memories tab
/// being torn down (for example when the app switches to the paywall or an account
/// notice) and an app relaunch. One draft per user, so one person's unsaved memory
/// never shows up in another person's session on a shared device.
@MainActor
protocol MemoryDraftStoring: AnyObject {
    func draft(for userID: UUID) throws -> MemoryDraft?
    /// Saves the draft, or removes the stored one when the draft has no content.
    func setDraft(_ draft: MemoryDraft, for userID: UUID) throws
    func clearDraft(for userID: UUID)
}

/// Text fields go to `UserDefaults` as one JSON blob per user, like the daily answer
/// drafts. Picked photos are written as files in a private directory, like the staged
/// daily answer media, so large images stay out of `UserDefaults`. Reads and writes
/// fail as a whole, so a restored draft never silently omits an attachment.
@MainActor
final class LocalMemoryDraftStore: MemoryDraftStoring {
    static let shared = LocalMemoryDraftStore()

    /// Identifies the current development storage shape. Change the storage key
    /// when that shape changes; development drafts do not need migration.
    private static let schemaVersion = 1

    private let defaults: UserDefaults
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// The photos last written per user, so typing in the title or note doesn't
    /// rewrite every photo file on each keystroke.
    private var writtenPhotos: [UUID: [UUID]] = [:]

    init(
        defaults: UserDefaults = .standard,
        directoryURL: URL = LocalMemoryDraftStore.defaultDirectoryURL()
    ) {
        self.defaults = defaults
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemoryDrafts", isDirectory: true)
    }

    func draft(for userID: UUID) throws -> MemoryDraft? {
        guard let data = defaults.data(forKey: key(for: userID)) else { return nil }
        let stored = try decoder.decode(StoredDraft.self, from: data)
        guard stored.photoCount >= 0, stored.photoDescriptions.count == stored.photoCount else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let photos = try (0..<stored.photoCount).map { index in
            MemoryDraftPhoto(
                data: try Data(contentsOf: photoURL(userID: userID, index: index)),
                accessibilityText: stored.photoDescriptions[index]
            )
        }
        // These files are what's on disk now, so typing in a restored draft doesn't rewrite them.
        writtenPhotos[userID] = photos.map(\.id)
        let draft = MemoryDraft(
            title: stored.title,
            date: stored.date,
            note: stored.note,
            photos: photos,
            place: stored.place
        )
        return draft.isEmpty ? nil : draft
    }

    func setDraft(_ draft: MemoryDraft, for userID: UUID) throws {
        guard !draft.isEmpty else {
            clearDraft(for: userID)
            return
        }

        let photoIDs = draft.photos.map(\.id)
        let stored = StoredDraft(
            schemaVersion: Self.schemaVersion,
            title: draft.title,
            date: draft.date,
            note: draft.note,
            photoCount: draft.photos.count,
            photoDescriptions: draft.photos.map(\.accessibilityText),
            place: draft.place
        )
        let data = try encoder.encode(stored)
        if writtenPhotos[userID] != photoIDs {
            try writePhotos(draft.photos.map(\.data), userID: userID)
            writtenPhotos[userID] = photoIDs
        }
        defaults.set(data, forKey: key(for: userID))
    }

    func clearDraft(for userID: UUID) {
        defaults.removeObject(forKey: key(for: userID))
        try? FileManager.default.removeItem(at: userDirectory(for: userID))
        writtenPhotos[userID] = nil
    }

    /// Writes the photos to a staging directory and swaps it in only when every file
    /// was written, so a failed write leaves the previously saved photos in place.
    private func writePhotos(_ photos: [Data], userID: UUID) throws {
        let fileManager = FileManager.default
        let directory = userDirectory(for: userID)
        guard !photos.isEmpty else {
            try? fileManager.removeItem(at: directory)
            return
        }

        let staging = directoryURL.appendingPathComponent(
            "\(userID.uuidString.lowercased()).staging",
            isDirectory: true
        )
        do {
            try? fileManager.removeItem(at: staging)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            for (index, data) in photos.enumerated() {
                try data.write(to: staging.appendingPathComponent("\(index)", isDirectory: false))
            }
            if fileManager.fileExists(atPath: directory.path) {
                _ = try fileManager.replaceItemAt(directory, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: directory)
            }
            return
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func key(for userID: UUID) -> String {
        "paeonia.memories.draft.v1.\(userID.uuidString)"
    }

    private func userDirectory(for userID: UUID) -> URL {
        directoryURL.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }

    private func photoURL(userID: UUID, index: Int) -> URL {
        userDirectory(for: userID).appendingPathComponent("\(index)", isDirectory: false)
    }
}

private struct StoredDraft: Codable {
    var schemaVersion: Int
    var title: String
    var date: Date
    var note: String
    var photoCount: Int
    var photoDescriptions: [String]
    var place: MemoryPlace?
}
