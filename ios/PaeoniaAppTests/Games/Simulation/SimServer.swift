import Foundation
@testable import PaeoniaApp

/// An in-memory copy of the Draw & Guess rules in `backend/convex/games.ts`,
/// shared by both phones. Every function checks what the real one checks, in
/// the same order, and fails with the same code and message, because the app
/// matches on them. Writes that take a client operation replay their stored
/// answer and refuse a replay whose request differs. A failing function changes
/// nothing, like a rolled back Convex mutation.
@MainActor
final class SimServer {
    let coupleID = UUID()
    let users: [UUID]
    let clock: SimClock
    private var random: SimRandom

    private(set) var settings: Settings?
    var game: Game?
    var rounds: [Round] = []
    private(set) var assets: [UUID: Asset] = [:]
    private var presence: [UUID: Date] = [:]
    private var invites: [UUID: Date] = [:]
    private var usedWords: [String: Set<String>] = [:]
    private var operations: [UUID: [UUID: (hash: String, response: Any)]] = [:]
    /// Upload reservations by the reserve operation, so a retried upload gets its asset back.
    private var uploadsByReservation: [UUID: UUID] = [:]
    /// Goes up with every change a `get_draw_and_guess` subscriber would see.
    private(set) var viewVersion = 0

    init(users: [UUID], clock: SimClock, random: SimRandom) {
        self.users = users
        self.clock = clock
        self.random = random
    }

    var now: Date { clock.now }

    func changed() {
        viewVersion += 1
    }

    // MARK: - Errors

    static func fail(_ code: String, _ message: String) -> PaeoniaConvexError {
        .server(code: code, message: message)
    }

    func noAccess() -> PaeoniaConvexError {
        Self.fail("42501", "active entitled game access is required")
    }

    func partner(of user: UUID) -> UUID {
        users.first { $0 != user } ?? user
    }

    // MARK: - Client operations

    /// `runClientOperation`: a replay returns the first answer, a replay with
    /// another request fails, and a failed run leaves no trace.
    func runOperation<T>(
        _ user: UUID,
        _ operation: SyncClientOperation,
        request: [String],
        work: () throws -> T
    ) throws -> T {
        let hash = request.joined(separator: "|")
        if let existing = operations[user]?[operation.id] {
            guard existing.hash == hash else {
                throw Self.fail("23505", "client operation replay hash mismatch")
            }
            guard let response = existing.response as? T else {
                throw Self.fail("23505", "client operation replay hash mismatch")
            }
            return response
        }
        guard operation.clientSequence > 0 else {
            throw Self.fail(
                "23514",
                "new row for relation \"client_operations\" violates check constraint "
                    + "\"client_operations_client_sequence_check\""
            )
        }
        let response = try work()
        operations[user, default: [:]][operation.id] = (hash, response)
        return response
    }

    // MARK: - Words

    private func drawChoices(language: GameLanguage) -> [RemoteDrawAndGuessChoice] {
        let points: [DrawAndGuessDifficulty: Int] = [.easy: 1, .medium: 2, .hard: 3]
        return [DrawAndGuessDifficulty.easy, .medium, .hard].map { difficulty in
            let key = "\(language.rawValue)-\(difficulty.rawValue)"
            let pool = Self.catalog[language]?[difficulty] ?? []
            var available = pool.filter { !(usedWords[key]?.contains($0.id) ?? false) }
            if available.isEmpty {
                usedWords[key] = []
                available = pool
            }
            let entry = random.pick(available)
            usedWords[key, default: []].insert(entry.id)
            return RemoteDrawAndGuessChoice(
                difficulty: difficulty,
                wordID: entry.id,
                word: entry.text,
                points: points[difficulty] ?? 1
            )
        }
    }

    // MARK: - Settings and the game

    func setSettings(user: UUID, playStyle: GamePlayStyle, language: GameLanguage) -> RemoteGameSettings {
        if var existing = settings {
            let languageChanged = existing.language != language
            existing.playStyle = playStyle
            existing.language = language
            existing.updatedBy = user
            existing.updatedAt = now
            settings = existing
            if languageChanged, var game, game.state == .choosingWord {
                game.choices = drawChoices(language: language)
                patch(&game)
                self.game = game
            }
        } else {
            settings = Settings(
                playStyle: playStyle,
                language: language,
                updatedBy: user,
                createdAt: now,
                updatedAt: now
            )
        }
        changed()
        guard let json = settingsJSON else { preconditionFailure("settings were just written") }
        return json
    }

    private var settingsJSON: RemoteGameSettings? {
        settings.map {
            RemoteGameSettings(
                coupleID: coupleID,
                playStyle: $0.playStyle,
                language: $0.language,
                updatedByUserID: $0.updatedBy,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
    }

    func ensureGame(user: UUID) throws -> RemoteEnsureGameResult {
        if let game {
            return RemoteEnsureGameResult(gameID: game.id, created: false)
        }
        guard let settings else { throw Self.fail("23514", "game settings are required") }
        game = Game(
            id: UUID(),
            state: .choosingWord,
            turnUser: user,
            turnNumber: 1,
            choices: drawChoices(language: settings.language),
            turnStartedAt: now,
            createdAt: now,
            updatedAt: now
        )
        changed()
        return RemoteEnsureGameResult(gameID: game?.id ?? UUID(), created: true)
    }

    func patch(_ game: inout Game) {
        game.version += 1
        game.updatedAt = now
    }

    /// `beginTurn`.
    func beginTurn(_ game: inout Game, drawer: UUID) {
        game.state = .choosingWord
        game.turnUser = drawer
        game.turnNumber += 1
        game.choices = drawChoices(language: settings?.language ?? .en)
        game.turnStartedAt = now
        patch(&game)
    }

    func roundIndex(_ id: UUID) -> Int? {
        rounds.firstIndex { $0.id == id }
    }

    func requireRound(_ id: UUID) throws -> Int {
        guard let index = roundIndex(id), game != nil else { throw noAccess() }
        return index
    }

    // MARK: - Uploads

    /// Reserve, upload and finalize in one step. The same reservation gives the same asset.
    /// A replayed reservation returns its asset, unless the orphan sweep deleted it.
    func uploadDrawing(user: UUID, data: Data, roundID: UUID, reserveOperation: SyncClientOperation) throws -> UUID {
        if let existing = uploadsByReservation[reserveOperation.id] {
            guard assets[existing]?.queuedForDelete == false else {
                throw Self.fail("42501", "media upload reservation is not available")
            }
            return existing
        }
        let id = UUID()
        assets[id] = Asset(id: id, owner: user, roundID: roundID, data: data, createdAt: now)
        uploadsByReservation[reserveOperation.id] = id
        return id
    }

    /// The weekly sweep: an upload nothing used within seven days is deleted.
    func sweepOrphanedUploads() -> Int {
        var swept = 0
        for (id, asset) in assets where !asset.queuedForDelete && now.timeIntervalSince(asset.createdAt) > 7 * 86_400 {
            if !rounds.contains(where: { $0.drawingAssetID == id }) {
                assets[id]?.queuedForDelete = true
                swept += 1
            }
        }
        return swept
    }

    func download(assetID: UUID) throws -> Data {
        guard let asset = assets[assetID], !asset.queuedForDelete else {
            throw GameDrawingTransferError.downloadUnavailable
        }
        return asset.data
    }

    // MARK: - Play together

    func sendInvite(user: UUID) throws -> RemoteInviteResult {
        if let previous = invites[user], previous > now.addingTimeInterval(-15 * 60) {
            throw Self.fail("53300", "you can send one invite every 15 minutes")
        }
        invites[user] = now
        changed()
        return RemoteInviteResult(sentAt: now)
    }

    func setPresence(user: UUID, present: Bool) {
        if present {
            presence[user] = now
        } else {
            presence[user] = nil
        }
        changed()
    }

    func presenceStamp(of user: UUID) -> Date? {
        presence[user]
    }

    /// Like the presence component, closes a game screen 60 seconds after its
    /// last heartbeat and tells the subscribers.
    func expirePresence() {
        let stale = presence.filter { now.timeIntervalSince($0.value) >= 60 }.map(\.key)
        guard !stale.isEmpty else { return }
        for user in stale {
            presence[user] = nil
        }
        changed()
    }
}

extension SimServer {
    // MARK: - The view

    /// `get_draw_and_guess` for `user`.
    func view(for user: UUID) -> RemoteDrawAndGuessState {
        let partnerID = partner(of: user)
        let moves = rounds.sorted { $0.number > $1.number }.prefix(21).map { json($0, for: user) }
        return RemoteDrawAndGuessState(
            userID: user,
            partnerUserID: partnerID,
            coupleID: coupleID,
            dataEpoch: "",
            settings: settingsJSON,
            game: game.map { game in
                RemoteDrawAndGuessGame(
                    id: game.id,
                    kind: "draw_and_guess",
                    state: game.state,
                    turnUserID: game.turnUser,
                    turnNumber: game.turnNumber,
                    currentRoundID: game.currentRoundID,
                    sharedPoints: game.shared,
                    myPoints: game.points[user] ?? 0,
                    partnerPoints: game.points[partnerID] ?? 0,
                    turnStartedAt: game.turnStartedAt,
                    version: game.version,
                    createdAt: game.createdAt,
                    updatedAt: game.updatedAt
                )
            },
            currentRound: moves.first,
            recentRounds: Array(moves.dropFirst()),
            choices: game?.state == .choosingWord && game?.turnUser == user ? game?.choices : nil,
            myPresent: presence[user] != nil,
            partnerPresent: presence[partnerID] != nil,
            lastInviteAt: invites[user]
        )
    }

    /// `get_draw_and_guess_round` for `user`.
    func round(_ id: UUID, for user: UUID) -> RemoteDrawAndGuessRound? {
        round(id).map { json($0, for: user) }
    }

    private func json(_ round: Round, for user: UUID) -> RemoteDrawAndGuessRound {
        RemoteDrawAndGuessRound(
            id: round.id,
            roundNumber: round.number,
            drawerUserID: round.drawer,
            guesserUserID: round.guesser,
            state: round.state,
            difficulty: round.difficulty,
            word: round.word,
            points: round.points,
            drawingMediaAssetID: round.drawingAssetID,
            drawingSubmittedAt: round.submittedAt,
            startedAt: round.startedAt,
            guesserFirstSeenAt: round.firstSeenAt,
            endedAt: round.endedAt,
            solveMs: round.solveMs,
            speedBonus: round.speedBonus,
            firstTryBonus: round.firstTryBonus,
            hintsUsed: round.hintsUsed,
            personalBest: round.personalBest,
            guesserReaction: round.reaction,
            // The simulation does not model stars.
            starredByMe: false,
            drawerResultSeenAt: round.drawerSeenAt,
            guesserResultSeenAt: round.guesserSeenAt,
            attempts: Array(round.attempts.suffix(200)),
            attemptCount: round.attempts.count
        )
    }

    func round(_ id: UUID) -> Round? {
        rounds.first { $0.id == id }
    }

    var currentRound: Round? {
        rounds.max { $0.number < $1.number }
    }
}
