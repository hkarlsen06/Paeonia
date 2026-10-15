import Foundation

/// A word the server refused for good. The screen puts it back in the field.
nonisolated struct MindMeldRefusedWord: Codable, Equatable, Sendable {
    let roundID: UUID
    let word: String
}

/// What this phone keeps of Mind Meld for one signed-in person. `state` is the
/// last result of `mindMeld:get_mind_meld`, so the game shows something at launch
/// and offline. `history` is the first page of "Our melds". The refused words
/// and refusal counts are only ever local.
nonisolated struct MindMeldLocalDocument: GamesPersistedDocument {
    var state: RemoteMindMeldState?
    var history: RemoteMindMeldHistoryPage?
    /// Words the server refused for good, until a screen shows the notice once.
    var refusedWords: [MindMeldRefusedWord] = []
    /// One entry per unexplained server refusal of a queued write, by operation id.
    var unexplainedRefusals: [UUID] = []
}

/// The Mind Meld cache. The live feed writes `state` and the screens read it.
/// Every method is keyed by the owner, so another account on this phone never
/// reads this person's relationship content.
protocol MindMeldCaching: Actor {
    func document(ownerUserID: UUID) -> MindMeldLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it, unless it is older than the cached state (see `isOlder(than:)`).
    func saveState(_ state: RemoteMindMeldState, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that is newer
    /// than the kept state is saved anyway, because a live write can carry a
    /// state from before the read. Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteMindMeldState, ownerUserID: UUID, ticket: Int) -> Bool
    /// Keeps the first page of "Our melds".
    func saveHistoryFirstPage(_ page: RemoteMindMeldHistoryPage, ownerUserID: UUID)
    func recordRefusedWord(_ refused: MindMeldRefusedWord, ownerUserID: UUID)
    /// Returns the refused words and forgets them.
    func takeRefusedWords(ownerUserID: UUID) -> [MindMeldRefusedWord]
    /// Counts one unexplained server refusal of a queued write and returns how
    /// many that write has had.
    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension MindMeldCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any MindMeldGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadMindMeld()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension MindMeldLocalDocument {
    private static let maxRefusals = 100
    private static let maxRefusedWords = 20

    /// Takes a state from the server unless it is older than the one kept.
    /// Returns whether it took it.
    mutating func accept(_ newState: RemoteMindMeldState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        return true
    }

    mutating func record(_ refused: MindMeldRefusedWord) {
        refusedWords.removeAll { $0.roundID == refused.roundID }
        refusedWords.append(refused)
        if refusedWords.count > Self.maxRefusedWords {
            refusedWords.removeFirst(refusedWords.count - Self.maxRefusedWords)
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

actor FileMindMeldCache: MindMeldCaching {
    static let shared = FileMindMeldCache()

    private var store: GamesDocumentStore<MindMeldLocalDocument>
    private var order = GamesStateWriteOrder()

    init(directoryURL: URL = FileMindMeldCache.defaultDirectoryURL()) {
        store = GamesDocumentStore(directoryURL: directoryURL, schemaVersion: 2)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        GamesDocumentStore<MindMeldLocalDocument>.defaultDirectoryURL(named: "MindMeldCache")
    }

    func document(ownerUserID: UUID) -> MindMeldLocalDocument {
        store.document(ownerUserID: ownerUserID)
    }

    func saveState(_ state: RemoteMindMeldState, ownerUserID: UUID) {
        guard state.userID == ownerUserID else { return }
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        store.save(kept, ownerUserID: ownerUserID)
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteMindMeldState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        store.save(kept, ownerUserID: ownerUserID)
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteMindMeldHistoryPage, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.history = page }
    }

    func recordRefusedWord(_ refused: MindMeldRefusedWord, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.record(refused) }
    }

    func takeRefusedWords(ownerUserID: UUID) -> [MindMeldRefusedWord] {
        var taken: [MindMeldRefusedWord] = []
        store.update(ownerUserID: ownerUserID) { document in
            taken = document.refusedWords
            document.refusedWords = []
        }
        return taken
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        store.update(ownerUserID: ownerUserID) { $0.recordRefusal(of: operationID) }
    }

    func clearAll() {
        order.overrideFetches()
        store.clear()
    }
}

/// For tests and the developer scenarios.
actor InMemoryMindMeldCache: MindMeldCaching {
    private var documents: [UUID: MindMeldLocalDocument] = [:]
    private var order = GamesStateWriteOrder()

    init(state: RemoteMindMeldState? = nil, ownerUserID: UUID? = nil) {
        guard let state, let ownerUserID else { return }
        documents[ownerUserID] = MindMeldLocalDocument(state: state)
    }

    func document(ownerUserID: UUID) -> MindMeldLocalDocument {
        documents[ownerUserID] ?? MindMeldLocalDocument()
    }

    func saveState(_ state: RemoteMindMeldState, ownerUserID: UUID) {
        guard state.userID == ownerUserID,
              documents[ownerUserID, default: MindMeldLocalDocument()].accept(state)
        else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteMindMeldState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var document = documents[ownerUserID, default: MindMeldLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteMindMeldHistoryPage, ownerUserID: UUID) {
        documents[ownerUserID, default: MindMeldLocalDocument()].history = page
    }

    func recordRefusedWord(_ refused: MindMeldRefusedWord, ownerUserID: UUID) {
        documents[ownerUserID, default: MindMeldLocalDocument()].record(refused)
    }

    func takeRefusedWords(ownerUserID: UUID) -> [MindMeldRefusedWord] {
        let words = documents[ownerUserID]?.refusedWords ?? []
        documents[ownerUserID]?.refusedWords = []
        return words
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: MindMeldLocalDocument()].recordRefusal(of: operationID)
    }

    func clearAll() {
        order.overrideFetches()
        documents = [:]
    }
}
