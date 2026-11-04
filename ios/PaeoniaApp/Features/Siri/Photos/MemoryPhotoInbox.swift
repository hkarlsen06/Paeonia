import Foundation

/// Photos from other apps waiting to go into a memory: files Siri passed in, or photos it
/// turned into Paeonia photos. They sit in a private temporary folder until the new-memory
/// form or "add to memory" takes them, and the privacy purge removes what is left.
nonisolated enum MemoryPhotoInbox {
    static let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("siri-photo-inbox", isDirectory: true)

    static func add(_ data: Data) throws -> UUID {
        let id = UUID()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL(id), options: [.atomic, .completeFileProtection])
        return id
    }

    static func add(fileAt url: URL) throws -> UUID {
        try add(Data(contentsOf: url))
    }

    static func contains(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(id).path)
    }

    static func data(for id: UUID) -> Data? {
        try? Data(contentsOf: fileURL(id))
    }

    /// Reads the photos and removes them from the inbox. A photo that is gone is skipped.
    static func take(_ ids: [UUID]) -> [Data] {
        ids.compactMap { id in
            defer { try? FileManager.default.removeItem(at: fileURL(id)) }
            return data(for: id)
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func fileURL(_ id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString, isDirectory: false)
    }
}
