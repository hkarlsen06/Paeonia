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
nonisolated struct ExquisiteCorpseLocalDocument: Codable, Equatable, Sendable {
    var state: RemoteExquisiteCorpseState?
    /// The first page of "Our creatures".
    var history: RemoteExquisiteCorpseHistoryPage?
    /// What the server last said about this person's star, by figure id. It also
    /// covers figures that are not in `state`.
    var stars: [UUID: Bool] = [:]
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
    /// Keeps what the server said about this person's star on figures, and
    /// patches the figures of the kept state and history page.
    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID)
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
    private static let maxStars = 500

    /// Takes a state from the server unless it is older than the one kept.
    /// Returns whether it took it.
    mutating func accept(_ newState: RemoteExquisiteCorpseState) -> Bool {
        if let state, newState.isOlder(than: state) {
            return false
        }
        state = newState
        return true
    }

    mutating func apply(stars answers: [UUID: Bool]) {
        stars.merge(answers) { _, answer in answer }
        if stars.count > Self.maxStars {
            // A figure with no entry reads as not starred, so the old unstarred ones go first.
            stars = stars.filter(\.value)
        }
        state?.apply(stars: answers)
        history = history?.applying(stars: answers)
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

    /// Bump when a stored type gains a required field. A file with another
    /// version reads as empty.
    private static let schemaVersion = 1

    private let directoryURL: URL
    private var order = GamesStateWriteOrder()

    init(directoryURL: URL = FileExquisiteCorpseCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExquisiteCorpseCache", isDirectory: true)
    }

    func document(ownerUserID: UUID) -> ExquisiteCorpseLocalDocument {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? PaeoniaConvexClient.decoder.decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return ExquisiteCorpseLocalDocument()
        }
        return envelope.document
    }

    func saveState(_ state: RemoteExquisiteCorpseState, ownerUserID: UUID) {
        guard state.userID == ownerUserID else { return }
        var kept = document(ownerUserID: ownerUserID)
        guard kept.accept(state) else { return }
        order.overrideFetches()
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
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
        update(ownerUserID: ownerUserID) { $0.state = kept.state }
        return true
    }

    func saveHistoryFirstPage(_ page: RemoteExquisiteCorpseHistoryPage, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.history = page }
    }

    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.apply(stars: stars) }
    }

    func saveIdea(_ ideaID: String?, partID: UUID, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.saveIdea(ideaID, partID: partID) }
    }

    func recordUnexplainedRefusal(operationID: UUID, ownerUserID: UUID) -> Int {
        var count = 0
        update(ownerUserID: ownerUserID) { count = $0.recordRefusal(of: operationID) }
        return count
    }

    func recordNotice(_ notice: ExquisiteCorpseStoredNotice, ownerUserID: UUID) {
        update(ownerUserID: ownerUserID) { $0.record(notice) }
    }

    func takeNotices(ownerUserID: UUID) -> [ExquisiteCorpseStoredNotice] {
        var taken: [ExquisiteCorpseStoredNotice] = []
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

    private func update(ownerUserID: UUID, _ change: (inout ExquisiteCorpseLocalDocument) -> Void) {
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
        let document: ExquisiteCorpseLocalDocument
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

    func saveStars(_ stars: [UUID: Bool], ownerUserID: UUID) {
        documents[ownerUserID, default: ExquisiteCorpseLocalDocument()].apply(stars: stars)
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
    /// would put the move off the screen again. A star never decides, because a
    /// person can change it on the server without the version moving.
    func isOlder(than other: RemoteExquisiteCorpseState) -> Bool {
        guard userID == other.userID, let game, let otherGame = other.game, game.id == otherGame.id else {
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

    /// Takes the server's answer for the person's star on the figures it carries.
    mutating func apply(stars: [UUID: Bool]) {
        currentFigure = currentFigure?.applying(stars: stars)
        recentFigures = recentFigures.map { $0.applying(stars: stars) }
    }

    /// This person's star on the figure in progress and the recent finished ones.
    var starValues: [UUID: Bool] {
        Dictionary(figures.map { ($0.id, $0.starredByMe) }, uniquingKeysWith: { first, _ in first })
    }

    /// The figure in progress and the recent finished ones.
    private var figures: [RemoteExquisiteCorpseFigure] {
        [currentFigure].compactMap(\.self) + recentFigures
    }
}

nonisolated extension RemoteExquisiteCorpseFigure {
    func applying(stars: [UUID: Bool]) -> RemoteExquisiteCorpseFigure {
        guard let starred = stars[id] else { return self }
        var figure = self
        figure.starredByMe = starred
        return figure
    }
}

nonisolated extension RemoteExquisiteCorpseHistoryPage {
    func applying(stars: [UUID: Bool]) -> RemoteExquisiteCorpseHistoryPage {
        RemoteExquisiteCorpseHistoryPage(
            figures: figures.map { $0.applying(stars: stars) },
            nextBeforeFigureNumber: nextBeforeFigureNumber
        )
    }

    /// The star state of every figure on the page.
    var starValues: [UUID: Bool] {
        Dictionary(figures.map { ($0.id, $0.starredByMe) }, uniquingKeysWith: { _, last in last })
    }
}
