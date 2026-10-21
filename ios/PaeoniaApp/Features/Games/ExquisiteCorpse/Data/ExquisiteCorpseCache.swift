import Foundation

/// A problem a background send found, kept until a screen shows it once.
nonisolated enum ExquisiteCorpseStoredNotice: String, Codable, Equatable, Sendable {
    /// A part could not be sent. It is back on the canvas.
    case partRejected
    /// A queued write other than a part was refused for good.
    case moveRejected
}

/// What this phone keeps for one signed-in person. `state` is the last result of
/// `exquisiteCorpse:get_exquisite_corpse`, so the game shows something at launch
/// and offline, and its idea deck works offline. The ideas, notices and refusals
/// are only ever local.
nonisolated struct ExquisiteCorpseLocalDocument: GamesPersistedDocument {
    var state: RemoteExquisiteCorpseState?
    /// The first page of "Our creatures".
    var history: RemoteExquisiteCorpseHistoryPage?
    /// The idea id on the chip, by part id, so a draft restores it. The latest 20.
    var ideas: [UUID: String] = [:]
    /// The part ids in `ideas`, oldest first.
    var ideaOrder: [UUID] = []
    var notices: [ExquisiteCorpseStoredNotice] = []
    /// One entry per unexplained server refusal of a queued write, by operation
    /// id. Offline tries and waits behind an earlier move never land here.
    var unexplainedRefusals: [UUID] = []
}

/// The Exquisite corpse cache. The live feed writes `state`, and the screens read
/// it. Every method is keyed by the owner, so another account on this phone never
/// reads this person's relationship content.
protocol ExquisiteCorpseCaching: Actor {
    func document(ownerUserID: UUID) -> ExquisiteCorpseLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it, unless it is older than the cached state (see `isOlder(than:)`).
    /// A state for another person is not saved.
    func saveState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that is newer
    /// than the kept state by what the server only moves forward is saved
    /// anyway, because a live write can carry a state from before the read.
    /// Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID, ticket: Int) -> Bool
    /// Keeps the first page of "Our creatures".
    func saveHistoryFirstPage(_ page: RemoteExquisiteCorpseHistoryPage, ownerUserID: UUID)
    /// Keeps the idea on the chip for a part. Nil removes it.
    func saveIdea(_ ideaID: String?, partID: UUID, ownerUserID: UUID)
    /// Counts one unexplained server refusal of a queued write and returns how
    /// many that write has had.
    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    func recordNotice(_ notice: ExquisiteCorpseStoredNotice, ownerUserID: UUID)
    /// Returns the notices and forgets them.
    func takeNotices(ownerUserID: UUID) -> [ExquisiteCorpseStoredNotice]
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension ExquisiteCorpseCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any ExquisiteCorpseGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadExquisiteCorpse()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension ExquisiteCorpseLocalDocument {
    private static let maxIdeas = 20
    private static let maxRefusals = 100

    /// Takes a state from the server unless it is older than the one kept.
    /// Returns whether it took it.
    mutating func accept(_ newState: RemoteExquisiteCorpseState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        return true
    }

    mutating func saveIdea(_ ideaID: String?, partID: UUID) {
        ideaOrder.removeAll { $0 == partID }
        ideas[partID] = ideaID
        guard ideaID != nil else { return }
        ideaOrder.append(partID)
        while ideaOrder.count > Self.maxIdeas {
            ideas[ideaOrder.removeFirst()] = nil
        }
    }

    mutating func record(_ notice: ExquisiteCorpseStoredNotice) {
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

actor FileExquisiteCorpseCache: ExquisiteCorpseCaching {
    static let shared = FileExquisiteCorpseCache()

    private var store: GamesDocumentStore<ExquisiteCorpseLocalDocument>
    private var order = GamesStateWriteOrder()

    init(directoryURL: URL = FileExquisiteCorpseCache.defaultDirectoryURL()) {
        store = GamesDocumentStore(directoryURL: directoryURL, schemaVersion: 2)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        GamesDocumentStore<ExquisiteCorpseLocalDocument>.defaultDirectoryURL(named: "ExquisiteCorpseCache")
    }

    func document(ownerUserID: UUID) -> ExquisiteCorpseLocalDocument {
        store.document(ownerUserID: ownerUserID)
    }

    func saveState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID) {
        guard state.userID == ownerUserID else { return }
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        store.save(kept, ownerUserID: ownerUserID)
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    @discardableResult
    func saveFetchedState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        store.save(kept, ownerUserID: ownerUserID)
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteExquisiteCorpseHistoryPage, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.history = page }
    }

    func saveIdea(_ ideaID: String?, partID: UUID, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.saveIdea(ideaID, partID: partID) }
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        store.update(ownerUserID: ownerUserID) { $0.recordRefusal(of: operationID) }
    }

    func recordNotice(_ notice: ExquisiteCorpseStoredNotice, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.record(notice) }
    }

    func takeNotices(ownerUserID: UUID) -> [ExquisiteCorpseStoredNotice] {
        var taken: [ExquisiteCorpseStoredNotice] = []
        store.update(ownerUserID: ownerUserID) { document in
            taken = document.notices
            document.notices = []
        }
        return taken
    }

    func clearAll() {
        order.overrideFetches()
        store.clear()
    }
}

/// For tests and the developer scenarios.
actor InMemoryExquisiteCorpseCache: ExquisiteCorpseCaching {
    private var documents: [UUID: ExquisiteCorpseLocalDocument] = [:]
    private var order = GamesStateWriteOrder()

    init(state: RemoteExquisiteCorpseState? = nil, ownerUserID: UUID? = nil) {
        guard let ownerUserID, let state else { return }
        documents[ownerUserID] = ExquisiteCorpseLocalDocument(state: state)
    }

    func document(ownerUserID: UUID) -> ExquisiteCorpseLocalDocument {
        documents[ownerUserID] ?? ExquisiteCorpseLocalDocument()
    }

    func saveState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID) {
        guard state.userID == ownerUserID,
              documents[ownerUserID, default: ExquisiteCorpseLocalDocument()].accept(state)
        else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    @discardableResult
    func saveFetchedState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var document = documents[ownerUserID, default: ExquisiteCorpseLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteExquisiteCorpseHistoryPage, ownerUserID: UUID) {
        documents[ownerUserID, default: ExquisiteCorpseLocalDocument()].history = page
    }

    func saveIdea(_ ideaID: String?, partID: UUID, ownerUserID: UUID) {
        documents[ownerUserID, default: ExquisiteCorpseLocalDocument()].saveIdea(ideaID, partID: partID)
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: ExquisiteCorpseLocalDocument()].recordRefusal(of: operationID)
    }

    func recordNotice(_ notice: ExquisiteCorpseStoredNotice, ownerUserID: UUID) {
        documents[ownerUserID, default: ExquisiteCorpseLocalDocument()].record(notice)
    }

    func takeNotices(ownerUserID: UUID) -> [ExquisiteCorpseStoredNotice] {
        let notices = documents[ownerUserID]?.notices ?? []
        documents[ownerUserID]?.notices = []
        return notices
    }

    func clearAll() {
        order.overrideFetches()
        documents = [:]
    }
}

// MARK: - State rules

nonisolated extension RemoteExquisiteCorpseState {
    /// This state is from before `other`. The game's version goes up with every
    /// move, and a reveal seen time is set once and stays. A state with a lower
    /// version, or with the same version and no reveal seen time on a figure
    /// where `other` has one, is an old answer that arrived late, such as a live
    /// feed update sent before a move this phone already read back. Keeping it
    /// would put the move off the screen again.
    func isOlder(than other: RemoteExquisiteCorpseState) -> Bool {
        guard userID == other.userID,
              dataEpoch == other.dataEpoch,
              let game,
              let otherGame = other.game,
              game.id == otherGame.id
        else {
            return false
        }
        if game.version != otherGame.version {
            return game.version < otherGame.version
        }
        let mine = Dictionary(figures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return other.figures.contains { theirs in
            guard theirs.myRevealSeenAt != nil, let own = mine[theirs.id] else { return false }
            return own.myRevealSeenAt == nil
        }
    }

    /// The figure in progress and the recent finished ones.
    private var figures: [RemoteExquisiteCorpseFigure] {
        [currentFigure].compactMap(\.self) + recentFigures
    }
}
