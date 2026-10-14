import Foundation

/// A problem a background send found, kept until a screen shows it once.
nonisolated enum GameStoredNotice: String, Codable, Equatable, Sendable {
    /// The picked word was no longer on offer, or it was not this person's turn.
    case wordRejected
    /// The same, and the drawing already made for that word is kept for the next one.
    case wordRejectedDrawingKept
    /// A drawing could not be sent. It is back on the canvas.
    case drawingRejected
    /// A guess or give up was refused for good. The round stays open.
    case moveRejected
}

/// The letters the guesser's hints showed in one round, kept so they survive
/// leaving the screen and relaunching.
nonisolated struct GameRoundHints: Codable, Equatable, Sendable {
    let roundID: UUID
    /// Answer slot indexes (spaces count as slots), in the order the hints showed them.
    var slotIndexes: [Int]
}

/// What this phone keeps for one signed-in person. `overview` is the last result
/// of `games:get_games_overview`, which every game and the Games tab share. The
/// rest belongs to Draw & Guess. `state` is the last result of
/// `drawAndGuess:get_draw_and_guess`, so the game shows something at launch and
/// offline. The hints, notices, refusals and drawings are only ever local.
nonisolated struct GamesLocalDocument: Codable, Equatable, Sendable {
    /// Nil until the first answer arrives. A file written before this field existed
    /// reads as nil, so the schema version stays.
    var overview: RemoteGamesOverview?
    var state: RemoteDrawAndGuessState?
    /// The hints of the latest rounds, oldest first.
    var hints: [GameRoundHints] = []
    var notices: [GameStoredNotice] = []
    /// One entry per unexplained server refusal of a queued write, by operation
    /// id. Offline tries and waits behind an earlier move never land here.
    var unexplainedRefusals: [UUID] = []
    /// "Our drawings": the first page, the records, and this person's stars.
    var drawings: GamesHistoryCache?
}

/// The Games cache. The live feeds write `overview` (shared) and `state`
/// (Draw & Guess), and the screens read them. Every method is keyed by the owner,
/// so another account on this phone never reads this person's relationship content.
protocol GamesCaching: Actor {
    func document(ownerUserID: UUID) -> GamesLocalDocument
    /// The overview feed's write. It wins over every one-shot overview read that
    /// started before it. An overview for another person is not saved.
    func saveOverview(_ overview: RemoteGamesOverview, ownerUserID: UUID)
    /// Takes a ticket for a one-shot overview read that is about to start.
    func beginOverviewFetch() -> Int
    /// Saves a one-shot overview read, unless a live write, a purge, or a read
    /// that started later was saved after `ticket` was taken. A read with newer
    /// settings than the kept ones is saved anyway. Returns whether it saved.
    @discardableResult
    func saveFetchedOverview(_ overview: RemoteGamesOverview, ownerUserID: UUID, ticket: Int) -> Bool
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
    /// Keeps the answer slots the hints of a round have shown.
    func saveHints(_ slotIndexes: [Int], roundID: UUID, ownerUserID: UUID)
    /// Keeps the first page of "Our drawings" and the stars it carries.
    func saveHistoryFirstPage(_ page: RemoteDrawAndGuessHistoryPage, ownerUserID: UUID)
    func saveRecords(_ records: RemoteDrawAndGuessRecords, ownerUserID: UUID)
    /// Keeps what the server said about this person's star on rounds.
    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID)
    /// This person has seen the settings screen or the "here's what your partner
    /// picked" moment for this couple, so setup never shows again. It is kept
    /// apart from the document, which a version change or a purge throws away.
    func hasSeenSettings(coupleID: UUID, ownerUserID: UUID) -> Bool
    func markSettingsSeen(coupleID: UUID, ownerUserID: UUID)
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
    nonisolated func fetchState(from gateway: any DrawAndGuessGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadDrawAndGuess()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }

    /// Reads the shared overview once and caches it. Returns false when the answer
    /// is for another person, which is not cached.
    nonisolated func fetchOverview(from gateway: any GamesGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginOverviewFetch()
        let loaded = try await gateway.loadOverview()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedOverview(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension GamesLocalDocument {
    private static let maxHintedRounds = 20
    private static let maxRefusals = 100

    mutating func saveHints(_ slotIndexes: [Int], roundID: UUID) {
        hints.removeAll { $0.roundID == roundID }
        hints.append(GameRoundHints(roundID: roundID, slotIndexes: slotIndexes))
        if hints.count > Self.maxHintedRounds {
            hints.removeFirst(hints.count - Self.maxHintedRounds)
        }
    }

    func hintedSlotIndexes(roundID: UUID) -> [Int] {
        hints.first { $0.roundID == roundID }?.slotIndexes ?? []
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
    private static let schemaVersion = 5

    private let directoryURL: URL
    private let defaults: UserDefaults
    private var order = GamesStateWriteOrder()
    private var overviewOrder = GamesStateWriteOrder()

    init(directoryURL: URL = FileGamesCache.defaultDirectoryURL(), defaults: UserDefaults = .standard) {
        self.directoryURL = directoryURL
        self.defaults = defaults
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

    func saveOverview(_ overview: RemoteGamesOverview, ownerUserID: UUID) {
        guard overview.userID == ownerUserID else { return }
        overviewOrder.overrideFetches()
        update(ownerUserID: ownerUserID) { $0.overview = overview }
    }

    func beginOverviewFetch() -> Int {
        overviewOrder.ticket()
    }

    func saveFetchedOverview(_ overview: RemoteGamesOverview, ownerUserID: UUID, ticket: Int) -> Bool {
        guard overview.userID == ownerUserID else { return false }
        let kept = document(ownerUserID: ownerUserID).overview
        guard overviewOrder.acceptFetch(ticket) || overview.hasNewerSettings(than: kept) else { return false }
        update(ownerUserID: ownerUserID) { $0.overview = overview }
        return true
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

    func saveHints(_ slotIndexes: [Int], roundID: UUID, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.saveHints(slotIndexes, roundID: roundID) }
    }

    func saveHistoryFirstPage(_ page: RemoteDrawAndGuessHistoryPage, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.saveHistoryFirstPage(page) }
    }

    func saveRecords(_ records: RemoteDrawAndGuessRecords, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.saveRecords(records) }
    }

    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.saveStars(stars) }
    }

    func hasSeenSettings(coupleID: UUID, ownerUserID: UUID) -> Bool {
        defaults.bool(forKey: Self.settingsSeenKey(coupleID: coupleID, ownerUserID: ownerUserID))
    }

    func markSettingsSeen(coupleID: UUID, ownerUserID: UUID) {
        defaults.set(true, forKey: Self.settingsSeenKey(coupleID: coupleID, ownerUserID: ownerUserID))
    }

    private static func settingsSeenKey(coupleID: UUID, ownerUserID: UUID) -> String {
        "paeonia.games.settingsSeen.\(ownerUserID.uuidString).\(coupleID.uuidString)"
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
        overviewOrder.overrideFetches()
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
    private var seenSettings: Set<[UUID]> = []
    private var order = GamesStateWriteOrder()
    private var overviewOrder = GamesStateWriteOrder()

    /// With a `state` and no `overview`, the overview is the one that state implies,
    /// so a test that passes one Draw & Guess state shows the same hub as before.
    init(
        state: RemoteDrawAndGuessState? = nil,
        overview: RemoteGamesOverview? = nil,
        ownerUserID: UUID? = nil,
        hasSeenSettings: Bool = false
    ) {
        guard let ownerUserID else { return }
        let overview = overview ?? state.map { RemoteGamesOverview(drawAndGuess: $0) }
        guard state != nil || overview != nil else { return }
        documents[ownerUserID] = GamesLocalDocument(overview: overview, state: state)
        if hasSeenSettings, let coupleID = overview?.settings?.coupleID {
            seenSettings.insert([coupleID, ownerUserID])
        }
    }

    func document(ownerUserID: UUID) -> GamesLocalDocument {
        documents[ownerUserID] ?? GamesLocalDocument()
    }

    func saveOverview(_ overview: RemoteGamesOverview, ownerUserID: UUID) {
        guard overview.userID == ownerUserID else { return }
        overviewOrder.overrideFetches()
        documents[ownerUserID, default: GamesLocalDocument()].overview = overview
    }

    func beginOverviewFetch() -> Int {
        overviewOrder.ticket()
    }

    func saveFetchedOverview(_ overview: RemoteGamesOverview, ownerUserID: UUID, ticket: Int) -> Bool {
        guard overview.userID == ownerUserID else { return false }
        let kept = documents[ownerUserID]?.overview
        guard overviewOrder.acceptFetch(ticket) || overview.hasNewerSettings(than: kept) else { return false }
        documents[ownerUserID, default: GamesLocalDocument()].overview = overview
        return true
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

    func saveHints(_ slotIndexes: [Int], roundID: UUID, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].saveHints(slotIndexes, roundID: roundID)
    }

    func saveHistoryFirstPage(_ page: RemoteDrawAndGuessHistoryPage, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].saveHistoryFirstPage(page)
    }

    func saveRecords(_ records: RemoteDrawAndGuessRecords, ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].saveRecords(records)
    }

    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID) {
        documents[ownerUserID, default: GamesLocalDocument()].saveStars(stars)
    }

    func hasSeenSettings(coupleID: UUID, ownerUserID: UUID) -> Bool {
        seenSettings.contains([coupleID, ownerUserID])
    }

    func markSettingsSeen(coupleID: UUID, ownerUserID: UUID) {
        seenSettings.insert([coupleID, ownerUserID])
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
        overviewOrder.overrideFetches()
        documents = [:]
    }
}

extension RemoteGamesOverview {
    /// This overview's settings changed after `kept`'s. The server only moves them
    /// forward, so a live write that carries older settings must not hide it.
    /// False when nothing is kept, such as after a purge.
    nonisolated func hasNewerSettings(than kept: RemoteGamesOverview?) -> Bool {
        guard let kept, let settings else { return false }
        guard let keptSettings = kept.settings else { return true }
        return settings.updatedAt > keptSettings.updatedAt
    }

    /// The overview a Draw & Guess state implies: the same couple and settings, and
    /// one `drawAndGuess` entry when either partner has it open or there is an invite.
    nonisolated init(drawAndGuess state: RemoteDrawAndGuessState) {
        let hasPresence = state.myPresent || state.partnerPresent || state.lastInviteAt != nil
        self.init(
            userID: state.userID,
            partnerUserID: state.partnerUserID,
            coupleID: state.coupleID,
            settings: state.settings,
            presence: hasPresence ? [
                RemoteGamePresence(
                    kind: .drawAndGuess,
                    myPresent: state.myPresent,
                    partnerPresent: state.partnerPresent,
                    lastInviteAt: state.lastInviteAt
                ),
            ] : []
        )
    }
}

extension RemoteDrawAndGuessState {
    /// This state is from before `other`. The server only ever moves these
    /// forward: the game's version goes up, a round gets its drawing, its first
    /// look and its result seen times once, attempts are only added, and a
    /// finished round stays finished. A state that has any of them behind `other` for the same
    /// game is an old answer that arrived late, such as a live feed update sent
    /// before a move that this phone already read back. Keeping it would put the
    /// move off the screen again.
    nonisolated func isOlder(than other: RemoteDrawAndGuessState) -> Bool {
        guard userID == other.userID,
              dataEpoch == other.dataEpoch,
              let game,
              let otherGame = other.game,
              game.id == otherGame.id
        else {
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
                || (theirs.drawerResultSeenAt != nil && mine.drawerResultSeenAt == nil)
                || (theirs.guesserResultSeenAt != nil && mine.guesserResultSeenAt == nil)
                || attempts(theirs) > attempts(mine) {
                return true
            }
        }
        return false
    }
}
