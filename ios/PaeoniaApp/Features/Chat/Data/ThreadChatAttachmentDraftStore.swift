import CryptoKit
import Foundation

nonisolated struct ThreadChatAttachmentDraft: Equatable, Sendable {
    let attachments: [ThreadChatAttachment]
    let caption: String
    /// Set by `read` when a video's file was gone, such as after a privacy purge. The
    /// draft no longer holds it, and the next save forgets it, so this shows once.
    var lostMedia = false

    var isEmpty: Bool { attachments.isEmpty && caption.isEmpty }
}

nonisolated struct ThreadChatAttachmentDraftKey: Hashable, Sendable {
    let ownerUserID: UUID
    let coupleID: UUID
    let subject: ThreadChatSubject

    var directoryName: String {
        "\(ownerUserID).\(coupleID).\(subject.kind.rawValue).\(subject.id)"
    }
}

nonisolated final class FileThreadChatAttachmentDraftStore: @unchecked Sendable {
    static let shared = FileThreadChatAttachmentDraftStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ChatAttachmentDrafts", isDirectory: true))

    private let directory: URL
    private let lock = NSLock()
    private var purgeGeneration = 0
    private var writers: [ThreadChatAttachmentDraftKey: UUID] = [:]

    init(directory: URL) { self.directory = directory }

    var generation: Int { lock.withLock { purgeGeneration } }

    func beginEditing(_ key: ThreadChatAttachmentDraftKey, generation: Int) -> UUID? {
        lock.withLock {
            guard generation == purgeGeneration else { return nil }
            let writerID = UUID()
            writers[key] = writerID
            return writerID
        }
    }

    func read(_ key: ThreadChatAttachmentDraftKey, generation: Int) throws -> ThreadChatAttachmentDraft? {
        try lock.withLock {
            guard generation == purgeGeneration else { return nil }
            let folder = directory.appendingPathComponent(key.directoryName, isDirectory: true)
            let url = folder.appendingPathComponent("draft.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let stored = try JSONDecoder().decode(StoredDraft.self, from: Data(contentsOf: url))
            var lostMedia = false
            let attachments = try stored.attachments.compactMap { item -> ThreadChatAttachment? in
                var attachment = item.attachment
                if let filename = item.filename {
                    attachment.local = .bytes(try Data(contentsOf: folder.appendingPathComponent(filename)))
                }
                if let videoURL = attachment.localFileURL, !FileManager.default.fileExists(atPath: videoURL.path) {
                    lostMedia = true
                    return nil
                }
                return attachment
            }
            return ThreadChatAttachmentDraft(attachments: attachments, caption: stored.caption, lostMedia: lostMedia)
        }
    }

    @discardableResult
    func save(
        _ draft: ThreadChatAttachmentDraft, for key: ThreadChatAttachmentDraftKey, generation: Int, writerID: UUID
    ) throws -> Bool {
        try lock.withLock {
            // A photo still loading in a dismissed composer must not recreate private files after a purge.
            guard generation == purgeGeneration, writers[key] == writerID else { return false }
            let folder = directory.appendingPathComponent(key.directoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let attachments = try draft.attachments.map { try storeAttachment($0, in: folder) }
            // Only the small manifest changes while someone dictates a caption or description.
            // Commit it after every file is safe, so a failed write preserves the previous draft.
            try JSONEncoder().encode(StoredDraft(attachments: attachments, caption: draft.caption)).write(
                to: folder.appendingPathComponent("draft.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            removeUnusedPhotos(in: folder, keeping: Set(attachments.compactMap(\.filename)))
            return true
        }
    }

    func remove(_ key: ThreadChatAttachmentDraftKey, generation: Int, writerID: UUID) throws {
        try lock.withLock {
            guard generation == purgeGeneration, writers[key] == writerID else { return }
            let url = directory.appendingPathComponent(key.directoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    /// The GIF and video files that any saved draft names, of every account on this phone.
    func fileNamesInAllDrafts() -> Set<String> {
        lock.withLock {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
            var names = Set<String>()
            for folder in folders {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("draft.json")),
                      let stored = try? JSONDecoder().decode(StoredDraft.self, from: data)
                else { continue }
                names.formUnion(stored.attachments.compactMap { $0.attachment.localFileURL?.lastPathComponent })
            }
            return names
        }
    }

    func clearAll() {
        lock.withLock {
            purgeGeneration += 1
            writers.removeAll()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// A photo gets its own file in the draft's folder. A GIF or a video stays where it was
    /// picked, and the manifest keeps its name.
    private func storeAttachment(_ attachment: ThreadChatAttachment, in folder: URL) throws -> StoredAttachment {
        switch attachment.local {
        case let .bytes(bytes):
            let filename = SHA256.hash(data: bytes).paeoniaHexString + ".photo"
            let url = folder.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            var metadata = attachment
            metadata.local = nil
            return StoredAttachment(filename: filename, attachment: metadata)
        case .file:
            return StoredAttachment(filename: nil, attachment: attachment)
        case nil:
            throw DraftFailure.attachmentUnavailable
        }
    }

    private func removeUnusedPhotos(in folder: URL, keeping filenames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "photo" && !filenames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private struct StoredDraft: Codable {
        let attachments: [StoredAttachment]
        let caption: String
    }

    private struct StoredAttachment: Codable {
        /// The file holding a photo's bytes. Nil for a GIF or a video.
        let filename: String?
        let attachment: ThreadChatAttachment
    }

    private enum DraftFailure: Error { case attachmentUnavailable }
}
