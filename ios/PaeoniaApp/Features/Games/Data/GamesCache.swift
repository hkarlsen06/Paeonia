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
    /// A guess or give up was refused for good. The round stays open.
    case moveRejected
}

/// What this phone keeps for one signed-in person. `state` is the last result
/// of `games:get_draw_and_guess`, so the hub and the game show something at
/// launch and offline. The rest is only ever local.
nonisolated struct GamesLocalDocument: Codable, Equatable, Sendable {
    var state: RemoteDrawAndGuessState?
    /// Rounds whose reveal this person has moved past.
    var acknowledgedRoundIDs: [UUID] = []
    /// Rounds whose save question this person answered with "not now", so it
    /// stays closed while the answer has not reached the server.
    var declinedSaveRoundIDs: [UUID] = []
    /// This person has seen the settings screen or the "here's what your partner
    /// picked" moment, so setup never shows again.
    var hasSeenSettings = false
    var notices: [GameStoredNotice] = []
    /// One entry per unexplained server refusal of a queued write, by operation
    /// id. Offline tries and waits behind an earlier move never land here.
    var unexplainedRefusals: [UUID] = []
}

/// The Games cache. The live feed writes `state`, and the screens read it.
/// Every method is keyed by the owner, so another account on this phone never
/// reads this person's relationship content.
protocol GamesCaching: Actor {
    func document(ownerUserID: UUID) -> GamesLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it, unless it is older than the cached state (see `isOlder(than:)`).
    func saveState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that is newer
    /// than the kept state by what the server only moves forward is saved
    /// anyway, because a live write can carry a state from before the read.
    /// Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID, ticket: Int) -> Bool
    /// Counts one unexplained server refusal of a queued write and returns how
    /// many that write has had.
    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    func acknowledgeRound(_ roundID: UUID, ownerUserID: UUID)
    func declineSave(_ roundID: UUID, ownerUserID: UUID)
    func markSettingsSeen(ownerUserID: UUID)
    func recordNotice(_ notice: GameStoredNotice, ownerUserID: UUID)
    /// Returns the notices and forgets them.
    func takeNotices(ownerUserID: UUID) -> [GameStoredNotice]
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension GamesCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any GamesGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadDrawAndGuess()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension GamesLocalDocument {
    private static let maxAcknowledgedRounds = 50
    private static let maxRefusals = 100

    mutating func acknowledge(_ roundID: UUID) {
        guard !acknowledgedRoundIDs.contains(roundID) else { return }
        acknowledgedRoundIDs.append(roundID)
        if acknowledgedRoundIDs.count > Self.maxAcknowledgedRounds {
            acknowledgedRoundIDs.removeFirst(acknowledgedRoundIDs.count - Self.maxAcknowledgedRounds)
        }
    }

    mutating func declineSave(_ roundID: UUID) {
        guard !declinedSaveRoundIDs.contains(roundID) else { return }
        declinedSaveRoundIDs.append(roundID)
        if declinedSaveRoundIDs.count > Self.maxAcknowledgedRounds {
            declinedSaveRoundIDs.removeFirst(declinedSaveRoundIDs.count - Self.maxAcknowledgedRounds)
        }
    }

    /// Takes a state from the server unless it is older than the one kept.
    /// Returns whether it took it.
    mutating func accept(_ newState: RemoteDrawAndGuessState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        return true
    }

    mutating func record(_ notice: GameStoredNotice) {
        if !notices.contains(notice) {
            notices.append(notice)
        }
    }

    mutating func recordRefusal(of operationID: UUID) -> Int {
        unexplainedRefusals.append(operationID)
        if unexplainedRefusals.count > Self.maxRefusals {
            unexplainedRefusals.removeFirst(unexplainedRefusals.count - Self.maxRefusals)
        }
        return unexplainedRefusals.count { $0 == operationID }
    }
}

/// Orders the writes of `state`. A live write and a purge beat every one-shot
/// read that started before them, and a read that started later beats one that
/// started earlier, so an older answer never replaces a newer one.
nonisolated struct GamesStateWriteOrder {
    private var lastTicket = 0
    private var lastWrite = 0

    mutating func ticket() -> Int {
        lastTicket += 1
        return lastTicket
    }

    /// A live write or a purge.
    mutating func overrideFetches() {
        lastWrite = ticket()
    }

    mutating func acceptFetch(_ ticket: Int) -> Bool {
        guard ticket > lastWrite else { return false }
        lastWrite = ticket
        return true
    }
}

actor FileGamesCache: GamesCaching {
    static let shared = FileGamesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 3

    private let directoryURL: URL
    private var order = GamesStateWriteOrder()

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
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID, ticket: Int) -> Bool {
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
        return true
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        var count = 0
        update(ownerUserID: ownerUserID) { count = $0.recordRefusal(of: operationID) }
        return count
    }

    func acknowledgeRound(_ roundID: UUID, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.acknowledge(roundID) }
    }

    func declineSave(_ roundID: UUID, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.declineSave(roundID) }
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
        order.overrideFetches()
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
    private var order = GamesStateWriteOrder()

    init(state: RemoteDrawAndGuessState? = nil, ownerUserID: UUID? = nil, hasSeenSettings: Bool = false) {
        if let state, let ownerUserID {
            documents[ownerUserID] = GamesLocalDocument(state: state, hasSeenSettings: hasSeenSettings)
        }
    }

    func document(ownerUserID: UUID) -> GamesLocalDocument {
        documents[ownerUserID] ?? GamesLocalDocument()
    }

    func saveState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID) {
        guard documents[ownerUserID, default: GamesLocalDocument()].accept(state) else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteDrawAndGuessState, ownerUserID: UUID, ticket: Int) -> Bool {
        var document = documents[ownerUserID, default: GamesLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: GamesLocalDocument()].recordRefusal(of: operationID)
    }

    func acknowledgeRound(_ roundID: UUID, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].acknowledge(roundID)
    }

    func declineSave(_ roundID: UUID, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].declineSave(roundID)
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
        order.overrideFetches()
        documents = [:]
    }
}

extension RemoteDrawAndGuessState {
    /// This state is from before `other`. The server only ever moves these
    /// forward: the game's version goes up, a round gets its drawing, its first
    /// look and its memory once, attempts are only added, and a finished round
    /// stays finished. A state that has any of them behind `other` for the same
    /// game is an old answer that arrived late, such as a live feed update sent
    /// before a move that this phone already read back. Keeping it would put the
    /// move off the screen again.
    nonisolated func isOlder(than other: RemoteDrawAndGuessState) -> Bool {
        guard userID == other.userID, let game, let otherGame = other.game, game.id == otherGame.id else {
            return false
        }
        if game.version < otherGame.version {
            return true
        }
        let rounds = Dictionary(
            ([currentRound].compactMap(\.self) + recentRounds).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for theirs in [other.currentRound].compactMap(\.self) + other.recentRounds {
            guard let mine = rounds[theirs.id] else { continue }
            let attempts = { (round: RemoteDrawAndGuessRound) in round.attemptCount ?? round.attempts.count }
            if (theirs.drawingMediaAssetID != nil && mine.drawingMediaAssetID == nil)
                || (theirs.state.isFinished && !mine.state.isFinished)
                || (theirs.guesserFirstSeenAt != nil && mine.guesserFirstSeenAt == nil)
                || (theirs.memoryID != nil && mine.memoryID == nil)
                || attempts(theirs) > attempts(mine) {
                return true
            }
        }
        return false
    }
}
