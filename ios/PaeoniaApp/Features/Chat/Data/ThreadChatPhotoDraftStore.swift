import CryptoKit
import Foundation

nonisolated struct ThreadChatPhotoDraft: Codable, Equatable, Sendable {
    let photos: [ThreadChatPhoto]
    let caption: String

    var isEmpty: Bool { photos.isEmpty && caption.isEmpty }
}

nonisolated struct ThreadChatPhotoDraftKey: Hashable, Sendable {
    let ownerUserID: UUID
    let coupleID: UUID
    let subject: ThreadChatSubject

    var directoryName: String {
        "\(ownerUserID).\(coupleID).\(subject.kind.rawValue).\(subject.id)"
    }
}

nonisolated final class FileThreadChatPhotoDraftStore: @unchecked Sendable {
    static let shared = FileThreadChatPhotoDraftStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ChatPhotoDrafts", isDirectory: true))

    private let directory: URL
    private let lock = NSLock()
    private var purgeGeneration = 0
    private var writers: [ThreadChatPhotoDraftKey: UUID] = [:]

    init(directory: URL) { self.directory = directory }

    var generation: Int { lock.withLock { purgeGeneration } }

    func beginEditing(_ key: ThreadChatPhotoDraftKey, generation: Int) -> UUID? {
        lock.withLock {
            guard generation == purgeGeneration else { return nil }
            let writerID = UUID()
            writers[key] = writerID
            return writerID
        }
    }

    func read(_ key: ThreadChatPhotoDraftKey, generation: Int) throws -> ThreadChatPhotoDraft? {
        try lock.withLock {
            guard generation == purgeGeneration else { return nil }
            let folder = directory.appendingPathComponent(key.directoryName, isDirectory: true)
            let url = folder.appendingPathComponent("draft.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let stored = try JSONDecoder().decode(StoredDraft.self, from: Data(contentsOf: url))
            let photos = try stored.photos.map { item in
                var photo = item.photo
                photo.data = try Data(contentsOf: folder.appendingPathComponent(item.filename))
                return photo
            }
            return ThreadChatPhotoDraft(photos: photos, caption: stored.caption)
        }
    }

    @discardableResult
    func save(
        _ draft: ThreadChatPhotoDraft, for key: ThreadChatPhotoDraftKey, generation: Int, writerID: UUID
    ) throws -> Bool {
        try lock.withLock {
            // A photo still loading in a dismissed composer must not recreate private files after a purge.
            guard generation == purgeGeneration, writers[key] == writerID else { return false }
            let folder = directory.appendingPathComponent(key.directoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let photos = try draft.photos.map { try storePhoto($0, in: folder) }
            // Only the small manifest changes while someone dictates a caption or description.
            // Commit it after every photo is safe, so a failed write preserves the previous draft.
            try JSONEncoder().encode(StoredDraft(photos: photos, caption: draft.caption)).write(
                to: folder.appendingPathComponent("draft.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            removeUnusedPhotos(in: folder, keeping: Set(photos.map(\.filename)))
            return true
        }
    }

    func remove(_ key: ThreadChatPhotoDraftKey, generation: Int, writerID: UUID) throws {
        try lock.withLock {
            guard generation == purgeGeneration, writers[key] == writerID else { return }
            let url = directory.appendingPathComponent(key.directoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    func clearAll() {
        lock.withLock {
            purgeGeneration += 1
            writers.removeAll()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func storePhoto(_ photo: ThreadChatPhoto, in folder: URL) throws -> StoredPhoto {
        guard let bytes = photo.data else { throw DraftFailure.photoUnavailable }
        let filename = SHA256.hash(data: bytes).paeoniaHexString + ".photo"
        let url = folder.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        var metadata = photo
        metadata.data = nil
        return StoredPhoto(filename: filename, photo: metadata)
    }

    private func removeUnusedPhotos(in folder: URL, keeping filenames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "photo" && !filenames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private struct StoredDraft: Codable {
        let photos: [StoredPhoto]
        let caption: String
    }

    private struct StoredPhoto: Codable {
        let filename: String
        let photo: ThreadChatPhoto
    }

    private enum DraftFailure: Error { case photoUnavailable }
}
