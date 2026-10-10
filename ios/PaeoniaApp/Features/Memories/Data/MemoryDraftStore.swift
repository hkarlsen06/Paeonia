import Foundation

/// Local persistence for a half-written new memory, so it survives the Memories tab
/// being torn down (for example when the app switches to the paywall or an account
/// notice) and an app relaunch. One draft per user, so one person's unsaved memory
/// never shows up in another person's session on a shared device.
@MainActor
protocol MemoryDraftStoring: AnyObject {
    func draft(for userID: UUID) -> MemoryDraft?
    /// Saves the draft, or removes the stored one when the draft has no content.
    func setDraft(_ draft: MemoryDraft, for userID: UUID)
    func clearDraft(for userID: UUID)
}

/// Text fields go to `UserDefaults` as one JSON blob per user, like the daily answer
/// drafts. Picked photos are written as files in a private directory, like the staged
/// daily answer media, so large images stay out of `UserDefaults`. A photo file that
/// can't be read back when restoring is skipped; the text and the other photos still
/// come back.
@MainActor
final class LocalMemoryDraftStore: MemoryDraftStoring {
    static let shared = LocalMemoryDraftStore()

    /// Bump when `StoredDraft` changes in a way that needs migration. New optional
    /// fields decode as nil on old data and don't need it.
    private static let schemaVersion = 1

    private let defaults: UserDefaults
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// The photos last written per user, so typing in the title or note doesn't
    /// rewrite every photo file on each keystroke.
    private var writtenPhotos: [UUID: [Data]] = [:]

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

    func draft(for userID: UUID) -> MemoryDraft? {
        guard let data = defaults.data(forKey: key(for: userID)),
              let stored = try? decoder.decode(StoredDraft.self, from: data)
        else { return nil }

        let photos = (0..<stored.photoCount).compactMap {
            try? Data(contentsOf: photoURL(userID: userID, index: $0))
        }
        // These files are what's on disk now, so typing in a restored draft doesn't rewrite them.
        writtenPhotos[userID] = photos
        let draft = MemoryDraft(title: stored.title, date: stored.date, note: stored.note, photos: photos)
        return draft.isEmpty ? nil : draft
    }

    func setDraft(_ draft: MemoryDraft, for userID: UUID) {
        guard !draft.isEmpty else {
            clearDraft(for: userID)
            return
        }

        // If the new photos can't be written (for example the disk is full), keep the
        // text and the photos saved before, rather than lose everything.
        var storedPhotoCount = draft.photos.count
        if writtenPhotos[userID] != draft.photos {
            if writePhotos(draft.photos, userID: userID) {
                writtenPhotos[userID] = draft.photos
            } else {
                storedPhotoCount = storedDraft(for: userID)?.photoCount ?? 0
            }
        }

        let stored = StoredDraft(
            schemaVersion: Self.schemaVersion,
            title: draft.title,
            date: draft.date,
            note: draft.note,
            photoCount: storedPhotoCount
        )
        if let data = try? encoder.encode(stored) {
            defaults.set(data, forKey: key(for: userID))
        }
    }

    func clearDraft(for userID: UUID) {
        defaults.removeObject(forKey: key(for: userID))
        try? FileManager.default.removeItem(at: userDirectory(for: userID))
        writtenPhotos[userID] = nil
    }

    /// Writes the photos to a staging directory and swaps it in only when every file
    /// was written, so a failed write leaves the previously saved photos in place.
    private func writePhotos(_ photos: [Data], userID: UUID) -> Bool {
        let fileManager = FileManager.default
        let directory = userDirectory(for: userID)
        guard !photos.isEmpty else {
            try? fileManager.removeItem(at: directory)
            return true
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
            return true
        } catch {
            try? fileManager.removeItem(at: staging)
            return false
        }
    }

    private func storedDraft(for userID: UUID) -> StoredDraft? {
        defaults.data(forKey: key(for: userID)).flatMap { try? decoder.decode(StoredDraft.self, from: $0) }
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
}
