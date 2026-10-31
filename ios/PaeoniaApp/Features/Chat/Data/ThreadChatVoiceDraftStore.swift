import Foundation

nonisolated struct ThreadChatVoiceDraft: Codable, Equatable, Sendable {
    let audio: Data
    let durationMs: Int
    let transcript: String
}

nonisolated struct ThreadChatVoiceDraftKey: Hashable, Sendable {
    let ownerUserID: UUID
    let coupleID: UUID
    let subject: ThreadChatSubject

    var filename: String {
        "\(ownerUserID).\(coupleID).\(subject.kind.rawValue).\(subject.id).json"
    }
}

nonisolated final class FileThreadChatVoiceDraftStore: @unchecked Sendable {
    static let shared = FileThreadChatVoiceDraftStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ChatVoiceDrafts", isDirectory: true))

    private let directory: URL
    private let lock = NSLock()
    private var purgeGeneration = 0
    private var writers: [ThreadChatVoiceDraftKey: UUID] = [:]

    init(directory: URL) { self.directory = directory }

    var generation: Int { lock.withLock { purgeGeneration } }

    func beginEditing(_ key: ThreadChatVoiceDraftKey, generation: Int) -> UUID? {
        lock.withLock {
            guard generation == purgeGeneration else { return nil }
            let writerID = UUID()
            writers[key] = writerID
            return writerID
        }
    }

    func read(_ key: ThreadChatVoiceDraftKey, generation: Int) throws -> ThreadChatVoiceDraft? {
        try lock.withLock {
            guard generation == purgeGeneration else { return nil }
            let url = directory.appendingPathComponent(key.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(ThreadChatVoiceDraft.self, from: Data(contentsOf: url))
        }
    }

    @discardableResult
    func save(
        _ draft: ThreadChatVoiceDraft, for key: ThreadChatVoiceDraftKey, generation: Int, writerID: UUID
    ) throws -> Bool {
        try lock.withLock {
            // A disappearing composer must not recreate private files after sign-out.
            guard generation == purgeGeneration, writers[key] == writerID else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(draft).write(
                to: directory.appendingPathComponent(key.filename),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return true
        }
    }

    func remove(_ key: ThreadChatVoiceDraftKey, generation: Int, writerID: UUID) throws {
        try lock.withLock {
            guard generation == purgeGeneration, writers[key] == writerID else { return }
            let url = directory.appendingPathComponent(key.filename)
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
}
