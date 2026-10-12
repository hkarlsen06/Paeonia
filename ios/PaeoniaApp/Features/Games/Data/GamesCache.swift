import Foundation

/// A problem a background send found, kept until a screen shows it once.
nonisolated enum GameStoredNotice: String, Codable, Equatable, Sendable {
    /// The picked word was no longer on offer, or it was not this person's turn.
    case wordRejected
    /// The same, and the drawing already made for that word is kept for the next one.
    case wordRejectedDrawingKept
    /// A drawing could not be sent. It is back on the canvas.
    case drawingRejected
    /// A drawing could not be saved to Memories.
    case saveRejected
}

/// What this phone keeps for one signed-in person. `state` is the last result
/// of `games:get_draw_and_guess`, so the hub and the game show something at
/// launch and offline. The rest is only ever local.
nonisolated struct GamesLocalDocument: Codable, Equatable, Sendable {
    var state: RemoteDrawAndGuessState?
    /// Rounds whose reveal this person has moved past.
    var acknowledgedRoundIDs: [UUID] = []
    /// This person has seen the settings screen or the "here's what your partner
    /// picked" moment, so setup never shows again.
    var hasSeenSettings = false
    var notices: [GameStoredNotice] = []
}

/// The Games cache. The live feed writes `state`, and the screens read it.
/// Every method is keyed by the owner, so another account on this phone never
/// reads this person's relationship content.
protocol GamesCaching: Actor {
    func document(ownerUserID: UUID) -> GamesLocalDocument
    /// The live feed's write. It always wins and moves `stateRevision`.
    func saveState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID)
    /// Goes up with each live write, so a slower read can tell it lost the race.
    func stateRevision(ownerUserID: UUID) -> Int
    /// Saves a one-shot read, unless a live write landed after `revision` was
    /// taken. The live copy is newer then. Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID, ifRevision revision: Int) -> Bool
    func acknowledgeRound(_ roundID: UUID, ownerUserID: UUID)
    func markSettingsSeen(ownerUserID: UUID)
    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID)
    /// Returns the notices and forgets them.
    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice]
    /// Called when the person leaves the paired state, so private content does not stay on the phone.
    func clearAll()
}

extension GamesCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any GamesGateway, ownerUserID: UUID) async throws -> Bool {
        let revision = await stateRevision(ownerUserID: ownerUserID)
        let loaded = try await gateway.loadDrawAndGuess()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ifRevision: revision)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension GamesLocalDocument {
    private static let maxAcknowledgedRounds = 50

    mutating func acknowledge(_ roundID: UUID) {
        guard !acknowledgedRoundIDs.contains(roundID) else { return }
        acknowledgedRoundIDs.append(roundID)
        if acknowledgedRoundIDs.count > Self.maxAcknowledgedRounds {
            acknowledgedRoundIDs.removeFirst(acknowledgedRoundIDs.count - Self.maxAcknowledgedRounds)
        }
    }

    mutating func record(_ notice: GameStoredNotice) {
        if !notices.contains(notice) {
            notices.append(notice)
        }
    }
}

actor FileGamesCache: GamesCaching {
    static let shared = FileGamesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL
    private var stateRevisions: [UUID: Int] = [:]

    init(directoryURL: URL = FileGamesCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GamesCache", isDirectory: true)
    }

    func document(ownerUserID: UUID) -> GamesLocalDocument {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? PaeoniaConvexClient.decoder.decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return GamesLocalDocument()
        }
        return envelope.document
    }

    func saveState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID) {
        stateRevisions[ownerUserID, default: 0] += 1
        update(ownerUserID: ownerUserID) { $0.state = state }
    }

    func stateRevision(ownerUserID: UUID) -> Int {
        stateRevisions[ownerUserID, default: 0]
    }

    func saveFetchedState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID, ifRevision revision: Int) -> Bool {
        guard stateRevision(ownerUserID: ownerUserID) == revision else { return false }
        update(ownerUserID: ownerUserID) { $0.state = state }
        return true
    }

    func acknowledgeRound(_ roundID: UUID, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.acknowledge(roundID) }
    }

    func markSettingsSeen(ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.hasSeenSettings = true }
    }

    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.record(notice) }
    }

    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice] {
        var taken: [GameStoredNotice] = []
        update(ownerUserID: ownerUserID) { document in
            taken = document.notices
            document.notices = []
        }
        return taken
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func update(ownerUserID: UUID, _ change: (inout GamesLocalDocument) -> Void) {
        var document = document(ownerUserID: ownerUserID)
        change(&document)
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, document: document)
        guard let data = try? PaeoniaConvexClient.encoder.encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let document: GamesLocalDocument
    }
}

/// For tests and the developer scenarios.
actor InMemoryGamesCache: GamesCaching {
    private var documents: [UUID: GamesLocalDocument] = [:]
    private var stateRevisions: [UUID: Int] = [:]

    init(state: RemoteDrawAndGuessState? = nil, ownerUserID: UUID? = nil, hasSeenSettings: Bool = false) {
        if let state, let ownerUserID {
            documents[ownerUserID] = GamesLocalDocument(state: state, hasSeenSettings: hasSeenSettings)
        }
    }

    func document(ownerUserID: UUID) -> GamesLocalDocument {
        documents[ownerUserID] ?? GamesLocalDocument()
    }

    func saveState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID) {
        stateRevisions[ownerUserID, default: 0] += 1
        documents[ownerUserID, default: GamesLocalDocument()].state = state
    }

    func stateRevision(ownerUserID: UUID) -> Int {
        stateRevisions[ownerUserID, default: 0]
    }

    func saveFetchedState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID, ifRevision revision: Int) -> Bool {
        guard stateRevision(ownerUserID: ownerUserID) == revision else { return false }
        documents[ownerUserID, default: GamesLocalDocument()].state = state
        return true
    }

    func acknowledgeRound(_ roundID: UUID, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].acknowledge(roundID)
    }

    func markSettingsSeen(ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].hasSeenSettings = true
    }

    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].record(notice)
    }

    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice] {
        let notices = documents[ownerUserID]?.notices ?? []
        documents[ownerUserID]?.notices = []
        return notices
    }

    func clearAll() {
        documents = [:]
    }
}
