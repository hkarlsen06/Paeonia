import Foundation

/// This person's favorites as the server last sent them, so stars are right offline and
/// right after launch. The live feed writes the whole list. A favorite the server just
/// confirmed is applied at once, before the live feed brings the same change.
protocol FavoritesCaching: Actor {
    func favorites(ownerUserID: UUID) -> [FavoriteRef]
    /// The live feed's write.
    func save(_ favorites: [FavoriteRef], ownerUserID: UUID)
    /// A write the server confirmed.
    func apply(_ target: FavoriteTarget, favorited: Bool, at date: Date, ownerUserID: UUID)
    /// Counts a save the server refused for good. The store tells the person once, then clears the count.
    func recordRefusal(ownerUserID: UUID)
    func takeRefusalCount(ownerUserID: UUID) -> Int
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

actor FileFavoritesCache: FavoritesCaching {
    static let shared = FileFavoritesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL

    init(directoryURL: URL = FileFavoritesCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FavoritesCache", isDirectory: true)
    }

    func favorites(ownerUserID: UUID) -> [FavoriteRef] {
        read(ownerUserID: ownerUserID).favorites
    }

    func save(_ favorites: [FavoriteRef], ownerUserID: UUID) {
        var stored = read(ownerUserID: ownerUserID)
        stored.favorites = favorites
        write(stored, ownerUserID: ownerUserID)
    }

    func apply(_ target: FavoriteTarget, favorited: Bool, at date: Date, ownerUserID: UUID) {
        var stored = read(ownerUserID: ownerUserID)
        stored.favorites = Self.applying(target, favorited: favorited, at: date, to: stored.favorites)
        write(stored, ownerUserID: ownerUserID)
    }

    func recordRefusal(ownerUserID: UUID) {
        var stored = read(ownerUserID: ownerUserID)
        stored.refusals += 1
        write(stored, ownerUserID: ownerUserID)
    }

    func takeRefusalCount(ownerUserID: UUID) -> Int {
        var stored = read(ownerUserID: ownerUserID)
        let count = stored.refusals
        guard count > 0 else { return 0 }
        stored.refusals = 0
        write(stored, ownerUserID: ownerUserID)
        return count
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// The list with one favorite added at the top, or removed. Newest first.
    nonisolated static func applying(
        _ target: FavoriteTarget,
        favorited: Bool,
        at date: Date,
        to favorites: [FavoriteRef]
    ) -> [FavoriteRef] {
        var result = favorites.filter { $0.target != target }
        if favorited {
            result.insert(FavoriteRef(target: target, createdAt: date), at: 0)
        }
        return result
    }

    private func read(ownerUserID: UUID) -> Envelope {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, favorites: [], refusals: 0)
        }
        return envelope
    }

    private func write(_ envelope: Envelope, ownerUserID: UUID) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        var favorites: [FavoriteRef]
        var refusals: Int
    }
}

/// The cache for previews, tests and the developer scenarios.
actor InMemoryFavoritesCache: FavoritesCaching {
    private var stored: [UUID: [FavoriteRef]]
    private var refusals: [UUID: Int] = [:]

    init(seed: [UUID: [FavoriteRef]] = [:]) {
        stored = seed
    }

    func favorites(ownerUserID: UUID) -> [FavoriteRef] {
        stored[ownerUserID] ?? []
    }

    func save(_ favorites: [FavoriteRef], ownerUserID: UUID) {
        stored[ownerUserID] = favorites
    }

    func apply(_ target: FavoriteTarget, favorited: Bool, at date: Date, ownerUserID: UUID) {
        stored[ownerUserID] = FileFavoritesCache.applying(
            target,
            favorited: favorited,
            at: date,
            to: stored[ownerUserID] ?? []
        )
    }

    func recordRefusal(ownerUserID: UUID) {
        refusals[ownerUserID, default: 0] += 1
    }

    func takeRefusalCount(ownerUserID: UUID) -> Int {
        refusals.removeValue(forKey: ownerUserID) ?? 0
    }

    func clearAll() {
        stored = [:]
        refusals = [:]
    }
}
