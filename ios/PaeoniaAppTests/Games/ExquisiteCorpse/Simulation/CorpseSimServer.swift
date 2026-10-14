import Foundation
@testable import PaeoniaApp

/// The Exquisite corpse backend in memory, with the rules of
/// `backend/convex/exquisiteCorpse.ts` and `lib/exquisiteCorpse.ts`: every check
/// and error code of `submit_exquisite_corpse_part`, client operation replay, the
/// hiding rule of `partJson`, the read rule of `canReadCorpseAsset`, the reveal
/// seen mark (first write wins) and stars. The couple already chose its settings.
@MainActor
final class CorpseSimServer {
    struct Part {
        let id: UUID
        let figureID: UUID
        let figureNumber: Int
        let index: Int
        let drawer: UUID
        let drawingAssetID: UUID
        let stripAssetID: UUID?
        let idea: RemoteExquisiteCorpseIdea?
        let createdAt: Date
    }

    struct Figure {
        let id: UUID
        let number: Int
        let starter: UUID
        let createdAt: Date
        var finishedAt: Date?
        var seenAt: [UUID: Date] = [:]
        var starredBy: Set<UUID> = []
    }

    struct Game {
        let id: UUID
        let creator: UUID
        var turnUser: UUID
        var turnStartedAt: Date
        var figureID: UUID?
        var figureNumber = 1
        var partIndex = 0
        var figuresFinished = 0
        var version = 1
        let createdAt: Date
        var updatedAt: Date
    }

    struct Asset {
        let id: UUID
        let owner: UUID
        let partID: UUID
        let purpose: String
        let data: Data
        let createdAt: Date
        var queuedForDelete = false
    }

    /// One request for an asset, as the server saw it, for the privacy check.
    struct Download {
        let user: UUID
        let assetID: UUID
        let purpose: String?
        let drawer: UUID?
        let figureFinished: Bool
        let allowed: Bool
    }

    let coupleID = UUID()
    let users: [UUID]
    let clock: SimClock
    private(set) var settings: RemoteGameSettings
    private(set) var game: Game?
    private(set) var figures: [Figure] = []
    private(set) var parts: [Part] = []
    var assets: [UUID: Asset] = [:]
    var downloads: [Download] = []
    var presence: [UUID: Date] = [:]
    var invites: [UUID: Date] = [:]
    private var operations: [UUID: [UUID: (hash: String, response: Any)]] = [:]
    var uploadsByReservation: [UUID: UUID] = [:]
    /// Goes up with every change a subscriber to the state or the overview would see.
    private(set) var viewVersion = 0

    /// Ideas for each part, 14 each. The deck is 12 of them, rotated by the part.
    static let ideas: [[RemoteExquisiteCorpseIdea]] = ["head", "body", "legs"].map { name in
        (1...14).map { RemoteExquisiteCorpseIdea(id: "\(name)-\($0)", text: "\(name) idea \($0)") }
    }

    init(users: [UUID], clock: SimClock) {
        self.users = users
        self.clock = clock
        settings = RemoteGameSettings(
            coupleID: coupleID,
            playStyle: .together,
            language: .en,
            updatedByUserID: users[0],
            createdAt: clock.now,
            updatedAt: clock.now
        )
    }

    var now: Date { clock.now }

    func changed() {
        viewVersion += 1
    }

    // MARK: - Errors

    func fail(_ code: String, _ message: String) -> PaeoniaConvexError {
        .server(code: code, message: message)
    }

    func noAccess() -> PaeoniaConvexError {
        fail("42501", "active entitled game access is required")
    }

    func uniqueViolation(_ constraint: String) -> PaeoniaConvexError {
        fail("23505", "duplicate key value violates unique constraint \"\(constraint)\"")
    }

    func partner(of user: UUID) -> UUID {
        users.first { $0 != user } ?? user
    }

    /// `runClientOperation`: a replay returns the first answer, a replay with
    /// another request fails, and a failed run leaves no trace.
    private func runOperation<T>(
        _ user: UUID,
        _ operation: SyncClientOperation,
        request: [String],
        work: () throws -> T
    ) throws -> T {
        let hash = request.joined(separator: "|")
        if let existing = operations[user]?[operation.id] {
            guard existing.hash == hash, let response = existing.response as? T else {
                throw fail("23505", "client operation replay hash mismatch")
            }
            return response
        }
        guard operation.clientSequence > 0 else {
            throw fail("23514", "client_operations_client_sequence_check")
        }
        let response = try work()
        operations[user, default: [:]][operation.id] = (hash, response)
        return response
    }

    // MARK: - The game

    func ensureGame(user: UUID) -> RemoteExquisiteCorpseEnsureResult {
        if let game {
            return RemoteExquisiteCorpseEnsureResult(gameID: game.id, created: false)
        }
        let created = Game(
            id: UUID(),
            creator: user,
            turnUser: user,
            turnStartedAt: now,
            createdAt: now,
            updatedAt: now
        )
        game = created
        changed()
        return RemoteExquisiteCorpseEnsureResult(gameID: created.id, created: true)
    }

    // MARK: - The turn

    func submitPart(
        user: UUID,
        payload: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID: UUID,
        stripAssetID: UUID?,
        operation: SyncClientOperation
    ) throws -> RemoteExquisiteCorpseSubmitPartResult {
        let index = payload.partIndex
        guard (0...2).contains(index) else { throw fail("22023", "part index must be 0, 1, or 2") }
        if index < 2, stripAssetID == nil { throw fail("22023", "the head and the body need a strip") }
        if index == 2, stripAssetID != nil { throw fail("22023", "the legs take no strip") }
        if let ideaID = payload.idea?.id, !Self.ideas[index].contains(where: { $0.id == ideaID }) {
            throw fail("22023", "the idea is not on the list for this part")
        }
        let request = [
            "submit_exquisite_corpse_part", payload.gameID.uuidString, payload.figureID.uuidString,
            payload.partID.uuidString, "\(index)", drawingAssetID.uuidString, stripAssetID?.uuidString ?? "",
            payload.idea?.id ?? "",
        ]
        return try runOperation(user, operation, request: request) {
            try accept(payload, from: user, drawingAssetID: drawingAssetID, stripAssetID: stripAssetID)
        }
    }

    /// `progressAfter`: the legs finish the figure and the next one starts with the head.
    private func advance(_ game: inout Game, after index: Int, figureID: UUID, by user: UUID) -> Bool {
        let isFinished = index == 2
        if isFinished, let at = figures.firstIndex(where: { $0.id == figureID }) {
            figures[at].finishedAt = now
        }
        game.figureID = isFinished ? nil : figureID
        game.figureNumber += isFinished ? 1 : 0
        game.partIndex = isFinished ? 0 : index + 1
        game.figuresFinished += isFinished ? 1 : 0
        game.turnUser = partner(of: user)
        game.turnStartedAt = now
        game.updatedAt = now
        game.version += 1
        return isFinished
    }

    /// The checks of `submit_exquisite_corpse_part` in the order the backend makes them.
    private func requireOpenTurn(_ payload: ExquisiteCorpseSubmitPartPayload, user: UUID) throws -> Game {
        guard let game, game.id == payload.gameID else { throw noAccess() }
        guard game.turnUser == user else { throw fail("42501", "it is not your turn") }
        guard payload.partIndex == game.partIndex else { throw fail("23514", "this part is out of date") }
        if payload.partIndex == 0 {
            guard game.figureID == nil else { throw fail("23514", "this figure is out of date") }
            if figures.contains(where: { $0.id == payload.figureID }) {
                throw uniqueViolation("exquisite_corpse_figures_pkey")
            }
        } else if payload.figureID != game.figureID {
            throw fail("23514", "this figure is out of date")
        }
        if parts.contains(where: { $0.id == payload.partID }) {
            throw uniqueViolation("exquisite_corpse_parts_pkey")
        }
        return game
    }

    private func accept(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        from user: UUID,
        drawingAssetID: UUID,
        stripAssetID: UUID?
    ) throws -> RemoteExquisiteCorpseSubmitPartResult {
        var game = try requireOpenTurn(payload, user: user)
        let index = payload.partIndex
        try requireUsable(drawingAssetID, user: user, partID: payload.partID, purpose: "exquisite_corpse_drawing")
        if let stripAssetID {
            try requireUsable(stripAssetID, user: user, partID: payload.partID, purpose: "exquisite_corpse_strip")
        }
        if index == 0 {
            figures.append(Figure(id: payload.figureID, number: game.figureNumber, starter: user, createdAt: now))
        }
        parts.append(Part(
            id: payload.partID,
            figureID: payload.figureID,
            figureNumber: game.figureNumber,
            index: index,
            drawer: user,
            drawingAssetID: drawingAssetID,
            stripAssetID: stripAssetID,
            idea: payload.idea.flatMap { idea in Self.ideas[index].first { $0.id == idea.id } },
            createdAt: now
        ))
        let isFinished = advance(&game, after: index, figureID: payload.figureID, by: user)
        self.game = game
        changed()
        return RemoteExquisiteCorpseSubmitPartResult(
            figureID: payload.figureID,
            partID: payload.partID,
            partIndex: index,
            figureFinished: isFinished,
            createdAt: now
        )
    }

    // MARK: - After the figure

    private func requireFinishedFigure(_ figureID: UUID) throws -> Int {
        guard let at = figures.firstIndex(where: { $0.id == figureID }) else { throw noAccess() }
        guard figures[at].finishedAt != nil else { throw fail("23514", "the creature is not finished yet") }
        return at
    }

    /// `mark_exquisite_corpse_reveal_seen`: the first time wins, for the caller's own side.
    func markRevealSeen(user: UUID, figureID: UUID) throws -> RemoteExquisiteCorpseRevealSeenResult {
        let at = try requireFinishedFigure(figureID)
        if let earlier = figures[at].seenAt[user] {
            return RemoteExquisiteCorpseRevealSeenResult(figureID: figureID, revealSeenAt: earlier)
        }
        figures[at].seenAt[user] = now
        changed()
        return RemoteExquisiteCorpseRevealSeenResult(figureID: figureID, revealSeenAt: now)
    }

    func setStar(user: UUID, figureID: UUID, starred: Bool) throws -> RemoteExquisiteCorpseStarResult {
        let at = try requireFinishedFigure(figureID)
        if starred != figures[at].starredBy.contains(user) {
            if starred { figures[at].starredBy.insert(user) } else { figures[at].starredBy.remove(user) }
            changed()
        }
        return RemoteExquisiteCorpseStarResult(figureID: figureID, starred: starred)
    }
}
