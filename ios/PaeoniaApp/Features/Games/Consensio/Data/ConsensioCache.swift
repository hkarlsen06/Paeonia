import Foundation

/// A move the server refused for good. The screen tells the person once. A
/// refused placement carries its topic and spot, so the screen puts the marker
/// back where it was.
nonisolated struct ConsensioRefusedMove: Codable, Equatable, Sendable {
    let roundID: UUID
    /// Nil for a guess.
    var topic: ConsensioTopicChoice?
    var spot: Int?
}

/// What this phone keeps of Consensio for one signed-in person. `state` is the
/// last result of `consensio:get_consensio`, so the game shows something at
/// launch and offline. `history` is the first page of "What we know". The refused
/// moves and refusal counts are only ever local.
nonisolated struct ConsensioLocalDocument: GamesPersistedDocument {
    var state: RemoteConsensioState?
    var history: RemoteConsensioHistoryPage?
    var refusedMoves: [ConsensioRefusedMove] = []
    /// One entry per unexplained server refusal of a queued write, by operation id.
    var unexplainedRefusals: [UUID] = []
}

/// The Consensio cache. The live feed writes `state` and the screens read it.
/// Every method is keyed by the owner, so another account on this phone never
/// reads this person's relationship content.
protocol ConsensioCaching: Actor {
    func document(ownerUserID: UUID) -> ConsensioLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it, unless it is older than the cached state (see `isOlder(than:)`).
    func saveState(_ state: RemoteConsensioState, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that is newer
    /// than the kept state is saved anyway. Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteConsensioState, ownerUserID: UUID, ticket: Int) -> Bool
    func saveHistoryFirstPage(_ page: RemoteConsensioHistoryPage, ownerUserID: UUID)
    func recordRefusedMove(_ refused: ConsensioRefusedMove, ownerUserID: UUID)
    /// Returns the refused moves and forgets them.
    func takeRefusedMoves(ownerUserID: UUID) -> [ConsensioRefusedMove]
    /// Counts one unexplained server refusal of a queued write and returns how
    /// many that write has had.
    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension ConsensioCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any ConsensioGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadConsensio()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension ConsensioLocalDocument {
    private static let maxRefusals = 100
    private static let maxRefusedMoves = 20

    /// Takes a state from the server unless it is older than the one kept.
    mutating func accept(_ newState: RemoteConsensioState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        return true
    }

    mutating func record(_ refused: ConsensioRefusedMove) {
        refusedMoves.removeAll { $0.roundID == refused.roundID }
        refusedMoves.append(refused)
        if refusedMoves.count > Self.maxRefusedMoves {
            refusedMoves.removeFirst(refusedMoves.count - Self.maxRefusedMoves)
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

actor FileConsensioCache: ConsensioCaching {
    static let shared = FileConsensioCache()

    private var store: GamesDocumentStore<ConsensioLocalDocument>
    private var order = GamesStateWriteOrder()

    init(directoryURL: URL = FileConsensioCache.defaultDirectoryURL()) {
        store = GamesDocumentStore(directoryURL: directoryURL, schemaVersion: 1)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        GamesDocumentStore<ConsensioLocalDocument>.defaultDirectoryURL(named: "ConsensioCache")
    }

    func document(ownerUserID: UUID) -> ConsensioLocalDocument {
        store.document(ownerUserID: ownerUserID)
    }

    func saveState(_ state: RemoteConsensioState, ownerUserID: UUID) {
        guard state.userID == ownerUserID else { return }
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        store.save(kept, ownerUserID: ownerUserID)
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteConsensioState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        store.save(kept, ownerUserID: ownerUserID)
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteConsensioHistoryPage, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.history = page }
    }

    func recordRefusedMove(_ refused: ConsensioRefusedMove, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.record(refused) }
    }

    func takeRefusedMoves(ownerUserID: UUID) -> [ConsensioRefusedMove] {
        var taken: [ConsensioRefusedMove] = []
        store.update(ownerUserID: ownerUserID) { document in
            taken = document.refusedMoves
            document.refusedMoves = []
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
actor InMemoryConsensioCache: ConsensioCaching {
    private var documents: [UUID: ConsensioLocalDocument] = [:]
    private var order = GamesStateWriteOrder()

    init(state: RemoteConsensioState? = nil, history: RemoteConsensioHistoryPage? = nil, ownerUserID: UUID? = nil) {
        guard let ownerUserID, state != nil || history != nil else { return }
        documents[ownerUserID] = ConsensioLocalDocument(state: state, history: history)
    }

    func document(ownerUserID: UUID) -> ConsensioLocalDocument {
        documents[ownerUserID] ?? ConsensioLocalDocument()
    }

    func saveState(_ state: RemoteConsensioState, ownerUserID: UUID) {
        guard state.userID == ownerUserID,
              documents[ownerUserID, default: ConsensioLocalDocument()].accept(state)
        else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteConsensioState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var document = documents[ownerUserID, default: ConsensioLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteConsensioHistoryPage, ownerUserID: UUID) {
        documents[ownerUserID, default: ConsensioLocalDocument()].history = page
    }

    func recordRefusedMove(_ refused: ConsensioRefusedMove, ownerUserID: UUID) {
        documents[ownerUserID, default: ConsensioLocalDocument()].record(refused)
    }

    func takeRefusedMoves(ownerUserID: UUID) -> [ConsensioRefusedMove] {
        let refused = documents[ownerUserID]?.refusedMoves ?? []
        documents[ownerUserID]?.refusedMoves = []
        return refused
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: ConsensioLocalDocument()].recordRefusal(of: operationID)
    }

    func clearAll() {
        order.overrideFetches()
        documents = [:]
    }
}
