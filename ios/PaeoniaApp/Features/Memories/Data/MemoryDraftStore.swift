import Foundation

/// Local persistence for a half-written new memory, so it survives the Memories tab
/// being torn down (for example when the app switches to the paywall or an account
/// notice) and an app relaunch. One draft per user, so one person's unsaved memory
/// never shows up in another person's session on a shared device.
protocol MemoryDraftStoring: AnyObject {
    func draft(for userID: UUID) throws -> MemoryDraft?
    /// Saves the draft, or removes the stored one when the draft has no content.
    func setDraft(_ draft: MemoryDraft, for userID: UUID) throws
    func clearDraft(for userID: UUID)
}

/// Text fields go to `UserDefaults` as one JSON blob per user, like the daily answer
/// drafts. Picked photos are written as files in a private directory, like the staged
/// daily answer media, so large images stay out of `UserDefaults`. A picked video is
/// already a file, so the blob keeps only its name. Reads and writes fail as a whole,
/// so a restored draft never silently omits an attachment.
final class LocalMemoryDraftStore: MemoryDraftStoring {
    static let shared = LocalMemoryDraftStore()

    /// Identifies the current development storage shape. Change the storage key
    /// when that shape changes; development drafts do not need migration.
    private static let schemaVersion = 2

    private let defaults: UserDefaults
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// The media last written per user, so typing in the title or note doesn't
    /// rewrite every photo file on each keystroke.
    private var writtenMedia: [UUID: [UUID]] = [:]

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
        let media = try stored.media.enumerated().map { index, item in
            let content: MemoryDraftMedia.Content
            if let video = item.video {
                content = .video(try video.prepared())
            } else {
                content = .photo(try Data(contentsOf: photoURL(userID: userID, index: index)))
            }
            return MemoryDraftMedia(content: content, accessibilityText: item.accessibilityText)
        }
        // These files are what's on disk now, so typing in a restored draft doesn't rewrite them.
        writtenMedia[userID] = media.map(\.id)
        let draft = MemoryDraft(
            title: stored.title,
            date: stored.date,
            note: stored.note,
            media: media,
            place: stored.place,
            visitID: stored.visitID
        )
        return draft.isEmpty ? nil : draft
    }

    func setDraft(_ draft: MemoryDraft, for userID: UUID) throws {
        guard !draft.isEmpty else {
            clearDraft(for: userID)
            return
        }

        let mediaIDs = draft.media.map(\.id)
        let stored = StoredDraft(
            schemaVersion: Self.schemaVersion,
            title: draft.title,
            date: draft.date,
            note: draft.note,
            media: draft.media.map { item in
                StoredMedia(accessibilityText: item.accessibilityText, video: item.video.map(StoredVideo.init))
            },
            place: draft.place,
            visitID: draft.visitID
        )
        let data = try encoder.encode(stored)
        if writtenMedia[userID] != mediaIDs {
            try writePhotos(draft.media, userID: userID)
            writtenMedia[userID] = mediaIDs
        }
        defaults.set(data, forKey: key(for: userID))
    }

    func clearDraft(for userID: UUID) {
        defaults.removeObject(forKey: key(for: userID))
        try? FileManager.default.removeItem(at: userDirectory(for: userID))
        writtenMedia[userID] = nil
    }

    /// Writes the photos to a staging directory and swaps it in only when every file
    /// was written, so a failed write leaves the previously saved photos in place. Each
    /// photo's file is named by its place in `media`.
    private func writePhotos(_ media: [MemoryDraftMedia], userID: UUID) throws {
        let fileManager = FileManager.default
        let directory = userDirectory(for: userID)
        let photos = media.enumerated().compactMap { index, item in item.photoData.map { (index, $0) } }
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
            for (index, data) in photos {
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

    /// The video files that any saved draft names, of every account on this phone.
    func videoFileNamesInAllDrafts() -> Set<String> {
        let prefix = key(forUserIDString: "")
        var names = Set<String>()
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            guard let data = value as? Data,
                  let stored = try? decoder.decode(StoredDraft.self, from: data)
            else { continue }
            names.formUnion(stored.media.compactMap(\.video?.fileName))
        }
        return names
    }

    private func key(for userID: UUID) -> String {
        key(forUserIDString: userID.uuidString)
    }

    private func key(forUserIDString userID: String) -> String {
        "paeonia.memories.draft.v\(Self.schemaVersion).\(userID)"
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
    var media: [StoredMedia]
    var place: MemoryPlace?
    var visitID: UUID?
}

private struct StoredMedia: Codable {
    var accessibilityText: String
    /// Nil for a photo, whose bytes are a file in the user's draft directory.
    var video: StoredVideo?
}

/// A prepared video by file name, since the app's container path can change between launches.
private struct StoredVideo: Codable {
    var fileName: String
    var width: Int
    var height: Int
    var durationMs: Int
    var byteSize: Int64

    init(_ video: PreparedVideo) {
        fileName = video.fileURL.lastPathComponent
        width = video.width
        height = video.height
        durationMs = video.durationMs
        byteSize = video.byteSize
    }

    /// Throws when the file is gone, so the draft fails as a whole instead of losing the video.
    func prepared() throws -> PreparedVideo {
        let fileURL = MemoryDraftMedia.videoDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw CocoaError(.fileReadNoSuchFile) }
        return PreparedVideo(fileURL: fileURL, width: width, height: height, durationMs: durationMs, byteSize: byteSize)
    }
}
