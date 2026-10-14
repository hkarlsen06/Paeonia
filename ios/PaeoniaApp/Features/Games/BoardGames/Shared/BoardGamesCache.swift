import Foundation

/// A problem a background send found, kept until that game's screen shows it once.
nonisolated enum BoardGameStoredNotice: Codable, Equatable, Sendable {
    /// A move was refused for good: the game had changed, or the move or the
    /// turn was not allowed. The board shows the server's state again.
    case moveRejected(GameKind)

    var kind: GameKind {
        switch self {
        case let .moveRejected(kind): kind
        }
    }
}

/// How far this phone has shown one game: the game and how many of its moves
/// were on screen. The moves after it are the ones the partner made since the
/// last look, which the board plays in order when it opens.
nonisolated struct BoardGameShownPosition: Codable, Equatable, Sendable {
    let gameNumber: Int
    let moveCount: Int
}

/// What this phone keeps for one signed-in person. `state` and `marks` are the
/// last results of the two live queries, so the board shows something at launch
/// and offline. The rest is only ever local.
nonisolated struct BoardGamesLocalDocument: Codable, Equatable, Sendable {
    var state: RemoteBoardGames?
    var marks: RemoteBoardGameMarks?
    /// By `GameKind` raw value.
    var shown: [String: BoardGameShownPosition] = [:]
    var notices: [BoardGameStoredNotice] = []
    /// One entry per unexplained server refusal of a queued write, by operation
    /// id. Offline tries and waits behind an earlier action never land here.
    var unexplainedRefusals: [UUID] = []

    func shownPosition(of kind: GameKind) -> BoardGameShownPosition? {
        shown[kind.rawValue]
    }
}

/// The board games cache. The live feeds write `state` and `marks`, and the
/// screens read them. Every method is keyed by the owner, so another account on
/// this phone never reads this person's relationship content.
protocol BoardGamesCaching: Actor {
    func document(ownerUserID: UUID) -> BoardGamesLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it. Per game it keeps the cached one when that is newer (see
    /// `RemoteBoardGame.isOlder(than:)`).
    func saveState(_ state: RemoteBoardGames, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read of the games that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that is newer
    /// than the kept state is saved anyway, because a live write can carry a
    /// state from before the read. Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteBoardGames, ownerUserID: UUID, ticket: Int) -> Bool
    /// Keeps the answer to a move, a rematch or `ensureGame`, unless the cached
    /// game is newer. Does nothing while no state is cached, because a game
    /// alone does not say whose couple it is. The read that follows a move
    /// fills the state in.
    func saveGame(_ game: RemoteBoardGame, ownerUserID: UUID)
    /// The marks live feed's write. It wins over every one-shot read of the
    /// marks that started before it.
    func saveMarks(_ marks: RemoteBoardGameMarks, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read of the marks that is about to start.
    func beginMarksFetch() -> Int
    /// Saves a one-shot read of the marks under the same ticket rule as
    /// `saveFetchedState`. Returns whether it saved.
    @discardableResult
    func saveFetchedMarks(_ marks: RemoteBoardGameMarks, ownerUserID: UUID, ticket: Int) -> Bool
    /// Remembers how far this phone has shown `kind`.
    func markShown(_ position: BoardGameShownPosition, kind: GameKind, ownerUserID: UUID)
    /// Counts one unexplained server refusal of a queued write and returns how
    /// many that write has had.
    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    func recordNotice(_ notice: BoardGameStoredNotice, ownerUserID: UUID)
    /// Returns the notices of one game and forgets them. The other games' stay.
    func takeNotices(kind: GameKind, ownerUserID: UUID) -> [BoardGameStoredNotice]
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension BoardGamesCaching {
    /// Reads the server's games once and caches them, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any BoardGamesGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadBoardGames()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }

    /// The same for both partners' marks.
    nonisolated func fetchMarks(from gateway: any BoardGamesGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginMarksFetch()
        let loaded = try await gateway.loadMarks()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedMarks(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension BoardGamesLocalDocument {
    private static let maxRefusals = 100

    /// Takes games from the server unless a game is older than the one kept.
    /// A game of a kind the server does not mention stays, because games are
    /// never deleted while the couple stays together and a missing one is an
    /// answer from before it was made. Returns false when every game offered
    /// was older, so the state did not change.
    mutating func accept(_ incoming: RemoteBoardGames) -> Bool {
        guard let kept = state, kept.userID == incoming.userID, kept.coupleID == incoming.coupleID else {
            state = incoming
            return true
        }
        var merged = RemoteBoardGames(
            userID: incoming.userID,
            partnerUserID: incoming.partnerUserID,
            coupleID: incoming.coupleID,
            games: kept.games
        )
        var tookAny = incoming.games.isEmpty
        for game in incoming.games {
            if let keptGame = kept.game(game.kind), game.isOlder(than: keptGame) { continue }
            merged = merged.replacing(game)
            tookAny = true
        }
        guard tookAny else { return false }
        state = merged
        return true
    }

    /// Takes one game, such as the answer to a move, unless it is older than the
    /// cached one. Returns whether it took it.
    mutating func accept(_ game: RemoteBoardGame) -> Bool {
        guard let kept = state else { return false }
        if let keptGame = kept.game(game.kind), game.isOlder(than: keptGame) { return false }
        state = kept.replacing(game)
        return true
    }

    mutating func record(_ notice: BoardGameStoredNotice) {
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

nonisolated extension RemoteBoardGames {
    /// This state is behind `other`: a game of it is an older picture of the
    /// same row (its version only goes up), or `other` has a game it lacks.
    /// Keeping it would put a move off the screen again, such as a live update
    /// sent before a move that this phone already read back.
    func isOlder(than other: RemoteBoardGames) -> Bool {
        guard userID == other.userID, coupleID == other.coupleID else { return false }
        return other.games.contains { theirs in
            guard let mine = game(theirs.kind) else { return true }
            return mine.isOlder(than: theirs)
        }
    }
}

actor FileBoardGamesCache: BoardGamesCaching {
    static let shared = FileBoardGamesCache()

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL
    private var order = GamesStateWriteOrder()
    private var marksOrder = GamesStateWriteOrder()

    init(directoryURL: URL = FileBoardGamesCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoardGamesCache", isDirectory: true)
    }

    func document(ownerUserID: UUID) -> BoardGamesLocalDocument {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? PaeoniaConvexClient.decoder.decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return BoardGamesLocalDocument()
        }
        return envelope.document
    }

    func saveState(_ state: RemoteBoardGames, ownerUserID: UUID) {
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteBoardGames, ownerUserID: UUID, ticket: Int) -> Bool {
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
        return true
    }

    func saveGame(_ game: RemoteBoardGame, ownerUserID: UUID) {
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(game) else { return }
        order.overrideFetches()
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
    }

    func saveMarks(_ marks: RemoteBoardGameMarks, ownerUserID: UUID) {
        marksOrder.overrideFetches()
        update(ownerUserID: ownerUserID) { $0.marks = marks }
    }

    func beginMarksFetch() -> Int {
        marksOrder.ticket()
    }

    func saveFetchedMarks(_ marks: RemoteBoardGameMarks, ownerUserID: UUID, ticket: Int) -> Bool {
        guard marksOrder.acceptFetch(ticket) else { return false }
        update(ownerUserID: ownerUserID) { $0.marks = marks }
        return true
    }

    func markShown(_ position: BoardGameShownPosition, kind: GameKind, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.shown[kind.rawValue] = position }
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        var count = 0
        update(ownerUserID: ownerUserID) { count = $0.recordRefusal(of: operationID) }
        return count
    }

    func recordNotice(_ notice: BoardGameStoredNotice, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.record(notice) }
    }

    func takeNotices(kind: GameKind, ownerUserID: UUID) -> [BoardGameStoredNotice] {
        var taken: [BoardGameStoredNotice] = []
        update(ownerUserID: ownerUserID) { document in
            taken = document.notices.filter { $0.kind == kind }
            document.notices.removeAll { $0.kind == kind }
        }
        return taken
    }

    func clearAll() {
        order.overrideFetches()
        marksOrder.overrideFetches()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func update(ownerUserID: UUID, _ change: (inout BoardGamesLocalDocument) -> Void) {
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
        let document: BoardGamesLocalDocument
    }
}

/// For tests and the developer scenarios.
actor InMemoryBoardGamesCache: BoardGamesCaching {
    private var documents: [UUID: BoardGamesLocalDocument] = [:]
    private var order = GamesStateWriteOrder()
    private var marksOrder = GamesStateWriteOrder()

    init(state: RemoteBoardGames? = nil, marks: RemoteBoardGameMarks? = nil, ownerUserID: UUID? = nil) {
        if let ownerUserID {
            documents[ownerUserID] = BoardGamesLocalDocument(state: state, marks: marks)
        }
    }

    func document(ownerUserID: UUID) -> BoardGamesLocalDocument {
        documents[ownerUserID] ?? BoardGamesLocalDocument()
    }

    func saveState(_ state: RemoteBoardGames, ownerUserID: UUID) {
        guard documents[ownerUserID, default: BoardGamesLocalDocument()].accept(state) else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteBoardGames, ownerUserID: UUID, ticket: Int) -> Bool {
        var document = documents[ownerUserID, default: BoardGamesLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func saveGame(_ game: RemoteBoardGame, ownerUserID: UUID) {
        guard documents[ownerUserID, default: BoardGamesLocalDocument()].accept(game) else { return }
        order.overrideFetches()
    }

    func saveMarks(_ marks: RemoteBoardGameMarks, ownerUserID: UUID) {
        marksOrder.overrideFetches()
        documents[ownerUserID, default: BoardGamesLocalDocument()].marks = marks
    }

    func beginMarksFetch() -> Int {
        marksOrder.ticket()
    }

    func saveFetchedMarks(_ marks: RemoteBoardGameMarks, ownerUserID: UUID, ticket: Int) -> Bool {
        guard marksOrder.acceptFetch(ticket) else { return false }
        documents[ownerUserID, default: BoardGamesLocalDocument()].marks = marks
        return true
    }

    func markShown(_ position: BoardGameShownPosition, kind: GameKind, ownerUserID: UUID) {
        documents[ownerUserID, default: BoardGamesLocalDocument()].shown[kind.rawValue] = position
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: BoardGamesLocalDocument()].recordRefusal(of: operationID)
    }

    func recordNotice(_ notice: BoardGameStoredNotice, ownerUserID: UUID) {
        documents[ownerUserID, default: BoardGamesLocalDocument()].record(notice)
    }

    func takeNotices(kind: GameKind, ownerUserID: UUID) -> [BoardGameStoredNotice] {
        let notices = (documents[ownerUserID]?.notices ?? []).filter { $0.kind == kind }
        documents[ownerUserID]?.notices.removeAll { $0.kind == kind }
        return notices
    }

    func clearAll() {
        order.overrideFetches()
        marksOrder.overrideFetches()
        documents = [:]
    }
}
