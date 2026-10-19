import Foundation

/// A move the server refused for good. The screen tells the person. A refused
/// send keeps its photo in the photo store under `roundID`, and the screen puts
/// the photo and the pin back on the check. It stays here, with its photo, until
/// the person sends it again or picks another photo, so quitting the app loses
/// nothing.
nonisolated struct GuessMySpotRefusedMove: Codable, Equatable, Sendable {
    let roundID: UUID
    /// Nil for a guess.
    var send: GuessMySpotSendPayload?
}

/// What this phone keeps of Guess my spot for one signed-in person. `state` is the
/// last result of `guessMySpot:get_guess_my_spot`, so the game shows something at
/// launch and offline. `history` is the last "Our guesses". The refused moves and
/// refusal counts are only ever local.
nonisolated struct GuessMySpotLocalDocument: GamesPersistedDocument {
    var state: RemoteGuessMySpotState?
    var history: RemoteGuessMySpotHistory?
    var refusedMoves: [GuessMySpotRefusedMove] = []
    /// One entry per unexplained server refusal of a queued write, by operation id.
    var unexplainedRefusals: [UUID] = []
}

/// The Guess my spot cache. The live feed writes `state` and the screens read it.
/// Every method is keyed by the owner, so another account on this phone never
/// reads this person's relationship content.
protocol GuessMySpotCaching: Actor {
    func document(ownerUserID: UUID) -> GuessMySpotLocalDocument
    /// The live feed's write. It wins over every one-shot read that started
    /// before it, unless it is older than the cached state (see `isOlder(than:)`).
    func saveState(_ state: RemoteGuessMySpotState, ownerUserID: UUID)
    /// Takes a ticket for a one-shot read that is about to start.
    func beginFetch() -> Int
    /// Saves a one-shot read, unless a live write, a purge, or a read that
    /// started later was saved after `ticket` was taken. A read that is newer
    /// than the kept state is saved anyway. Returns whether it saved.
    @discardableResult
    func saveFetchedState(_ state: RemoteGuessMySpotState, ownerUserID: UUID, ticket: Int) -> Bool
    /// Taken before a history read starts. A purge after it makes `saveHistory` drop that read.
    func historyTicket() -> Int
    func saveHistory(_ history: RemoteGuessMySpotHistory, ownerUserID: UUID, ticket: Int)
    func recordRefusedMove(_ refused: GuessMySpotRefusedMove, ownerUserID: UUID)
    /// Forgets one refused move, once the screen has dealt with it.
    func forgetRefusedMove(roundID: UUID, ownerUserID: UUID)
    /// Counts one unexplained server refusal of a queued write and returns how
    /// many that write has had.
    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    /// Called when the person leaves the paired state, so private content does not
    /// stay on the phone. A one-shot read still on its way is not saved after it.
    func clearAll()
}

extension GuessMySpotCaching {
    /// Reads the server's state once and caches it, unless the live feed cached
    /// something newer while the request ran. Returns false when the answer is
    /// for another person, which is not cached.
    nonisolated func fetchState(from gateway: any GuessMySpotGateway, ownerUserID: UUID) async throws -> Bool {
        let ticket = await beginFetch()
        let loaded = try await gateway.loadGuessMySpot()
        guard loaded.userID == ownerUserID else { return false }
        await saveFetchedState(loaded, ownerUserID: ownerUserID, ticket: ticket)
        return true
    }
}

/// Rules shared by the file and in-memory caches.
nonisolated extension GuessMySpotLocalDocument {
    private static let maxRefusals = 100
    private static let maxRefusedMoves = 20

    /// Takes a state from the server unless it is older than the one kept.
    mutating func accept(_ newState: RemoteGuessMySpotState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        return true
    }

    mutating func record(_ refused: GuessMySpotRefusedMove) {
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

actor FileGuessMySpotCache: GuessMySpotCaching {
    static let shared = FileGuessMySpotCache()

    private var store: GamesDocumentStore<GuessMySpotLocalDocument>
    private var order = GamesStateWriteOrder()
    private var purges = 0

    init(directoryURL: URL = FileGuessMySpotCache.defaultDirectoryURL()) {
        store = GamesDocumentStore(directoryURL: directoryURL, schemaVersion: 1)
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        GamesDocumentStore<GuessMySpotLocalDocument>.defaultDirectoryURL(named: "GuessMySpotCache")
    }

    func document(ownerUserID: UUID) -> GuessMySpotLocalDocument {
        store.document(ownerUserID: ownerUserID)
    }

    func saveState(_ state: RemoteGuessMySpotState, ownerUserID: UUID) {
        guard state.userID == ownerUserID else { return }
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        store.save(kept, ownerUserID: ownerUserID)
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteGuessMySpotState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var kept = document(ownerUserID: ownerUserID)
        let isNewer = kept.state.map { $0.isOlder(than: state) } ?? false
        guard kept.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        store.save(kept, ownerUserID: ownerUserID)
        return true
    }

    func historyTicket() -> Int {
        purges
    }

    func saveHistory(_ history: RemoteGuessMySpotHistory, ownerUserID: UUID, ticket: Int) {
        guard ticket == purges else { return }
        store.update(ownerUserID: ownerUserID) { $0.history = history }
    }

    func recordRefusedMove(_ refused: GuessMySpotRefusedMove, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.record(refused) }
    }

    func forgetRefusedMove(roundID: UUID, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.refusedMoves.removeAll { $0.roundID == roundID } }
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        store.update(ownerUserID: ownerUserID) { $0.recordRefusal(of: operationID) }
    }

    func clearAll() {
        order.overrideFetches()
        purges += 1
        store.clear()
    }
}

/// For tests and the developer scenarios.
actor InMemoryGuessMySpotCache: GuessMySpotCaching {
    private var documents: [UUID: GuessMySpotLocalDocument] = [:]
    private var order = GamesStateWriteOrder()
    private var purges = 0

    init(state: RemoteGuessMySpotState? = nil, history: RemoteGuessMySpotHistory? = nil, ownerUserID: UUID? = nil) {
        guard let ownerUserID, state != nil || history != nil else { return }
        documents[ownerUserID] = GuessMySpotLocalDocument(state: state, history: history)
    }

    func document(ownerUserID: UUID) -> GuessMySpotLocalDocument {
        documents[ownerUserID] ?? GuessMySpotLocalDocument()
    }

    func saveState(_ state: RemoteGuessMySpotState, ownerUserID: UUID) {
        guard state.userID == ownerUserID,
              documents[ownerUserID, default: GuessMySpotLocalDocument()].accept(state)
        else { return }
        order.overrideFetches()
    }

    func beginFetch() -> Int {
        order.ticket()
    }

    func saveFetchedState(_ state: RemoteGuessMySpotState, ownerUserID: UUID, ticket: Int) -> Bool {
        guard state.userID == ownerUserID else { return false }
        var document = documents[ownerUserID, default: GuessMySpotLocalDocument()]
        let isNewer = document.state.map { $0.isOlder(than: state) } ?? false
        guard document.accept(state), order.acceptFetch(ticket) || isNewer else { return false }
        documents[ownerUserID] = document
        return true
    }

    func historyTicket() -> Int {
        purges
    }

    func saveHistory(_ history: RemoteGuessMySpotHistory, ownerUserID: UUID, ticket: Int) {
        guard ticket == purges else { return }
        documents[ownerUserID, default: GuessMySpotLocalDocument()].history = history
    }

    func recordRefusedMove(_ refused: GuessMySpotRefusedMove, ownerUserID: UUID) {
        documents[ownerUserID, default: GuessMySpotLocalDocument()].record(refused)
    }

    func forgetRefusedMove(roundID: UUID, ownerUserID: UUID) {
        documents[ownerUserID]?.refusedMoves.removeAll { $0.roundID == roundID }
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: GuessMySpotLocalDocument()].recordRefusal(of: operationID)
    }

    func clearAll() {
        order.overrideFetches()
        purges += 1
        documents = [:]
    }
}
