import Foundation

/// The stripped photos of sends that have not reached the server, one file per
/// person and round. The queued send carries only the round id, so the queue
/// stays small, and the photo is here while the phone is offline. The send
/// handler removes the file once the server has the round.
nonisolated protocol GuessMySpotPhotoStoring: Sendable {
    func save(_ jpeg: Data, ownerUserID: UUID, roundID: UUID) throws
    func photo(ownerUserID: UUID, roundID: UUID) -> Data?
    func remove(ownerUserID: UUID, roundID: UUID)
    /// The privacy purge calls this on sign-out and when a relationship ends.
    func clearAll()
}

nonisolated final class FileGuessMySpotPhotoStore: GuessMySpotPhotoStoring, @unchecked Sendable {
    static let shared = FileGuessMySpotPhotoStore()

    private let directoryURL: URL
    private let lock = NSLock()

    init(directoryURL: URL = FileGuessMySpotPhotoStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    /// In Application Support, so the system never removes a photo that waits to be sent.
    static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuessMySpotPhotos", isDirectory: true)
    }

    func save(_ jpeg: Data, ownerUserID: UUID, roundID: UUID) throws {
        try lock.withLock {
            let url = fileURL(ownerUserID: ownerUserID, roundID: roundID)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func photo(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { try? Data(contentsOf: fileURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func remove(ownerUserID: UUID, roundID: UUID) {
        lock.withLock { try? FileManager.default.removeItem(at: fileURL(ownerUserID: ownerUserID, roundID: roundID)) }
    }

    func clearAll() {
        lock.withLock { try? FileManager.default.removeItem(at: directoryURL) }
    }

    private func fileURL(ownerUserID: UUID, roundID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(ownerUserID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("\(roundID.uuidString.lowercased()).jpg", isDirectory: false)
    }
}

/// For tests and the developer scenarios.
nonisolated final class InMemoryGuessMySpotPhotoStore: GuessMySpotPhotoStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var photos: [String: Data] = [:]

    init() {}

    func save(_ jpeg: Data, ownerUserID: UUID, roundID: UUID) throws {
        lock.withLock { photos[key(ownerUserID, roundID)] = jpeg }
    }

    func photo(ownerUserID: UUID, roundID: UUID) -> Data? {
        lock.withLock { photos[key(ownerUserID, roundID)] }
    }

    func remove(ownerUserID: UUID, roundID: UUID) {
        lock.withLock { photos[key(ownerUserID, roundID)] = nil }
    }

    func clearAll() {
        lock.withLock { photos = [:] }
    }

    private func key(_ owner: UUID, _ round: UUID) -> String {
        "\(owner.uuidString):\(round.uuidString)"
    }
}
