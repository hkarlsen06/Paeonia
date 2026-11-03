import Foundation

nonisolated struct PiccanteShownPosition: Codable, Equatable, Sendable {
    var number: Int
    var bites: Int
}
nonisolated struct PiccanteDocument: GamesPersistedDocument {
    var state: RemotePiccanteState?
    var shown: PiccanteShownPosition?
    var lastFinished: RemotePiccanteGame?
    var refusedMoves: [PiccanteMove] = []
    var refused = false
    var refusals: [UUID] = []
}
protocol PiccanteCaching: Actor {
    func document(ownerUserID: UUID) -> PiccanteDocument
    func saveState(_ state: RemotePiccanteState, ownerUserID: UUID)
    func saveShown(_ shown: PiccanteShownPosition, ownerUserID: UUID)
    func recordRefusal(operationID: UUID, ownerUserID: UUID) -> Int
    func refuse(_ move: PiccanteMove, ownerUserID: UUID)
    func takeRefused(ownerUserID: UUID) -> [PiccanteMove]
    func clearAll()
}
actor PiccanteCache: PiccanteCaching {
    static let shared = PiccanteCache()
    private var store: GamesDocumentStore<PiccanteDocument>
    init(directoryURL: URL = GamesDocumentStore<PiccanteDocument>.defaultDirectoryURL(named: "PiccanteCache")) {
        store = GamesDocumentStore(directoryURL: directoryURL, schemaVersion: 1)
    }
    func document(ownerUserID: UUID) -> PiccanteDocument { store.document(ownerUserID: ownerUserID) }
    func saveState(_ state: RemotePiccanteState, ownerUserID: UUID) {
        guard state.userID == ownerUserID else { return }
        store.update(ownerUserID: ownerUserID) { document in
            guard document.state.map({ !state.isOlder(than: $0) }) ?? true else { return }
            document.state = state
            if let result = state.unseenResult { document.lastFinished = result }
            if let game = state.game, game.phase == .finished { document.lastFinished = game }
        }
    }
    func saveShown(_ shown: PiccanteShownPosition, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.shown = shown }
    }
    func recordRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        store.update(ownerUserID: ownerUserID) {
            $0.refusals.append(operationID)
            $0.refusals = Array($0.refusals.suffix(100))
            return $0.refusals.count { $0 == operationID }
        }
    }
    func refuse(_ move: PiccanteMove, ownerUserID: UUID) {
        store.update(ownerUserID: ownerUserID) { $0.refusedMoves.append(move) }
    }
    func takeRefused(ownerUserID: UUID) -> [PiccanteMove] {
        store.update(ownerUserID: ownerUserID) {
            let moves = $0.refusedMoves
            $0.refusedMoves = []
            return moves
        }
    }
    func clearAll() { store.clear() }
}

nonisolated struct PiccanteLiveFeed: LiveFeed {
    let name = "piccante"
    var activation: LiveFeedActivation { .gameState(.piccante) }
    let cache: any PiccanteCaching
    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else { return }
        for await result in live.subscribe("piccante:get_piccante", as: RemotePiccanteState.self) {
            guard !Task.isCancelled else { return }
            guard case .value(let state) = result else { continue }
            await cache.saveState(state, ownerUserID: session.userID)
            guard !Task.isCancelled else { return }
            LocalStoreChanges.post(.games, ownerUserID: session.userID)
        }
    }
}

actor InMemoryPiccanteCache: PiccanteCaching {
    private var documents: [UUID: PiccanteDocument] = [:]
    init(state: RemotePiccanteState? = nil) {
        if let state {
            documents[state.userID] = PiccanteDocument(
                state: state, lastFinished: state.unseenResult ?? (state.game?.phase == .finished ? state.game : nil))
        }
    }
    func document(ownerUserID: UUID) -> PiccanteDocument { documents[ownerUserID] ?? PiccanteDocument() }
    func saveState(_ state: RemotePiccanteState, ownerUserID: UUID) {
        guard state.userID == ownerUserID, documents[ownerUserID]?.state.map({ !state.isOlder(than: $0) }) ?? true
        else { return }
        documents[ownerUserID, default: PiccanteDocument()].state = state
        if let result = state.unseenResult { documents[ownerUserID]?.lastFinished = result }
        if let game = state.game, game.phase == .finished { documents[ownerUserID]?.lastFinished = game }
    }
    func saveShown(_ shown: PiccanteShownPosition, ownerUserID: UUID) {
        documents[ownerUserID, default: PiccanteDocument()].shown = shown
    }
    func recordRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        documents[ownerUserID, default: PiccanteDocument()].refusals.append(operationID)
        return documents[ownerUserID]?.refusals.count { $0 == operationID } ?? 0
    }
    func refuse(_ move: PiccanteMove, ownerUserID: UUID) {
        documents[ownerUserID, default: PiccanteDocument()].refused = true
    }
    func takeRefused(ownerUserID: UUID) -> [PiccanteMove] {
        let moves = documents[ownerUserID]?.refusedMoves ?? []
        documents[ownerUserID]?.refusedMoves = []
        return moves
    }
    func clearAll() { documents = [:] }
}
