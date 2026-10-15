import Foundation

/// What a games cache keeps for one signed-in person.
nonisolated protocol GamesPersistedDocument: Codable, Equatable, Sendable {
    /// The empty document, for a person with no file yet.
    init()
}

/// The file storage behind the games caches: one JSON file per signed-in person
/// under `directoryURL`. A cache actor owns one store, so all access is serial.
///
/// A person's file is read and decoded once. The decoded document stays in
/// memory, and a write encodes it again only when the document changed.
nonisolated struct GamesDocumentStore<Document: GamesPersistedDocument> {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let document: Document
    }

    private let directoryURL: URL
    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private let schemaVersion: Int
    private var loaded: [UUID: Document] = [:]
    /// People whose last write failed, so the next save writes even an unchanged document.
    private var unwritten: Set<UUID> = []

    init(directoryURL: URL, schemaVersion: Int) {
        self.directoryURL = directoryURL
        self.schemaVersion = schemaVersion
    }

    /// The directory the app keeps `name` in.
    static func defaultDirectoryURL(named name: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    mutating func document(ownerUserID: UUID) -> Document {
        if let document = loaded[ownerUserID] { return document }
        let document = readFile(ownerUserID: ownerUserID) ?? Document()
        loaded[ownerUserID] = document
        return document
    }

    /// Keeps `document`, and writes the file unless nothing changed.
    mutating func save(_ document: Document, ownerUserID: UUID) {
        guard document != self.document(ownerUserID: ownerUserID) || unwritten.contains(ownerUserID) else { return }
        loaded[ownerUserID] = document
        if writeFile(document, ownerUserID: ownerUserID) {
            unwritten.remove(ownerUserID)
        } else {
            unwritten.insert(ownerUserID)
        }
    }

    /// Changes the person's document in memory and writes it if the change made
    /// a difference. Returns what `change` returns.
    @discardableResult
    mutating func update<Result>(ownerUserID: UUID, _ change: (inout Document) -> Result) -> Result {
        var copy = document(ownerUserID: ownerUserID)
        let result = change(&copy)
        save(copy, ownerUserID: ownerUserID)
        return result
    }

    /// Forgets every document in memory and deletes the files.
    mutating func clear() {
        loaded = [:]
        unwritten = []
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func readFile(ownerUserID: UUID) -> Document? {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? PaeoniaConvexClient.decoder.decode(Envelope.self, from: data),
              envelope.schemaVersion == schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return nil
        }
        return envelope.document
    }

    /// Returns false when the file could not be written, for example on a full disk.
    private func writeFile(_ document: Document, ownerUserID: UUID) -> Bool {
        let envelope = Envelope(schemaVersion: schemaVersion, ownerUserID: ownerUserID, document: document)
        do {
            let data = try PaeoniaConvexClient.encoder.encode(envelope)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: ownerUserID), options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }
}
