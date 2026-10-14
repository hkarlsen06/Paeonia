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
    struct Round {
        let id: UUID
        let number: Int
        let drawer: UUID
        let guesser: UUID
        var state: DrawAndGuessRoundState
        let difficulty: DrawAndGuessDifficulty
        let wordID: String?
        let word: String
        let points: Int
        var drawingAssetID: UUID?
        var submittedAt: Date?
        let startedAt: Date
        var firstSeenAt: Date?
        var endedAt: Date?
        var solveMs: Int?
        var speedBonus = 0
        var firstTryBonus = 0
        var hintsUsed = 0
        var personalBest = false
        var reaction: DrawAndGuessReaction?
        var drawerSeenAt: Date?
        var guesserSeenAt: Date?
        var attempts: [RemoteDrawAndGuessAttempt] = []
    }

    struct Asset {
        let id: UUID
        let owner: UUID
        /// The round the drawing was reserved for.
        let roundID: UUID
        let data: Data
        let createdAt: Date
        var queuedForDelete = false
    }

    struct Game {
        let id: UUID
        var state: DrawAndGuessGameState
        var turnUser: UUID
        var turnNumber: Int
        var currentRoundID: UUID?
        var choices: [RemoteDrawAndGuessChoice]?
        var shared = 0
        var points: [UUID: Int] = [:]
        var turnStartedAt: Date
        var version = 1
        let createdAt: Date
        var updatedAt: Date
    }

    struct Settings {
        var playStyle: GamePlayStyle
        var language: GameLanguage
        var updatedBy: UUID
        let createdAt: Date
        var updatedAt: Date
    }

    let coupleID = UUID()
    let users: [UUID]
    let clock: SimClock
    private var random: SimRandom

    private(set) var settings: Settings?
    private(set) var game: Game?
    private(set) var rounds: [Round] = []
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

    private var now: Date { clock.now }

    private func changed() {
        viewVersion += 1
    }

    // MARK: - Errors

    static func fail(_ code: String, _ message: String) -> PaeoniaConvexError {
        .server(code: code, message: message)
    }

    private func noAccess() -> PaeoniaConvexError {
        Self.fail("42501", "active entitled game access is required")
    }

    private func partner(of user: UUID) -> UUID {
        users.first { $0 != user } ?? user
    }

    // MARK: - Client operations

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
                "new row for relation \"client_operations\" violates check constraint \"client_operations_client_sequence_check\""
            )
        }
        let response = try work()
        operations[user, default: [:]][operation.id] = (hash, response)
        return response
    }

    // MARK: - Words

    static let catalog: [GameLanguage: [DrawAndGuessDifficulty: [(id: String, text: String)]]] = [
        .en: [
            .easy: [("cat", "cat"), ("sun", "sun"), ("tree", "tree"), ("fish", "fish"), ("ice-cream", "ice cream")],
            .medium: [("umbrella", "umbrella"), ("hot-dog", "hot dog"), ("rocket", "rocket"), ("guitar", "guitar")],
            .hard: [("volcano", "volcano"), ("pirate-ship", "pirate ship"), ("lighthouse", "lighthouse")],
        ],
        .nb: [
            .easy: [("sol", "sol"), ("maane", "måne"), ("katt", "katt"), ("aal", "ål")],
            .medium: [("brunost", "brunost"), ("fjord", "fjord"), ("isbjorn", "isbjørn")],
            .hard: [("nordlys", "nordlys"), ("aerfugl", "ærfugl"), ("vaffel-jern", "vaffel jern")],
        ],
    ]

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

    static func normalizeWordText(_ input: String) -> String {
        input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    /// `normalizeCustomWord`.
    static func normalizeCustomWord(_ input: String) throws -> String {
        let word = normalizeWordText(input)
        let parts = word.split(separator: " ", omittingEmptySubsequences: false)
        let letters = word.filter { $0 != " " }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzæøå")
        guard parts.count <= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(allowed.contains) }),
              (2...20).contains(letters.count)
        else {
            throw fail("23514", "custom word must be 2 to 20 letters in at most three words")
        }
        return word
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
            settings = Settings(playStyle: playStyle, language: language, updatedBy: user, createdAt: now, updatedAt: now)
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

    private func patch(_ game: inout Game) {
        game.version += 1
        game.updatedAt = now
    }

    /// `beginTurn`.
    private func beginTurn(_ game: inout Game, drawer: UUID) {
        game.state = .choosingWord
        game.turnUser = drawer
        game.turnNumber += 1
        game.choices = drawChoices(language: settings?.language ?? .en)
        game.turnStartedAt = now
        patch(&game)
    }

    private func roundIndex(_ id: UUID) -> Int? {
        rounds.firstIndex { $0.id == id }
    }

    private func requireRound(_ id: UUID) throws -> Int {
        guard let index = roundIndex(id), game != nil else { throw noAccess() }
        return index
    }

    // MARK: - The turn

    func pickWord(user: UUID, _ pick: GamePickWordPayload, operation: SyncClientOperation) throws -> RemotePickedWord {
        let customWord = pick.choice == .custom ? try Self.normalizeCustomWord(pick.word) : nil
        let seenWordID = pick.choice == .custom ? "" : (pick.wordID ?? "")
        let request = [
            "pick_draw_word", pick.gameID.uuidString, pick.roundID.uuidString, pick.choice.rawValue,
            customWord ?? "", seenWordID,
        ]
        return try runOperation(user, operation, request: request) {
            guard var game, game.id == pick.gameID else { throw noAccess() }
            guard game.turnUser == user else { throw Self.fail("42501", "it is not your turn") }
            guard game.state == .choosingWord else {
                throw Self.fail("23514", "a word was already chosen for this turn")
            }
            guard roundIndex(pick.roundID) == nil else {
                throw Self.fail("23505", "duplicate key value violates unique constraint \"game_moves_pkey\"")
            }
            let word: String
            let wordID: String?
            if let customWord {
                word = customWord
                wordID = nil
            } else {
                guard let choice = game.choices?.first(where: { $0.difficulty == pick.choice }) else {
                    throw Self.fail("23514", "word choice is not available")
                }
                guard choice.wordID == seenWordID else { throw Self.fail("23514", "word choice is out of date") }
                word = choice.word
                wordID = choice.wordID
            }
            let points = [DrawAndGuessDifficulty.easy: 1, .medium: 2, .hard: 3, .custom: 2][pick.choice] ?? 2
            rounds.append(Round(
                id: pick.roundID,
                number: game.turnNumber,
                drawer: user,
                guesser: partner(of: user),
                state: .drawing,
                difficulty: pick.choice,
                wordID: wordID,
                word: word,
                points: points,
                startedAt: now
            ))
            game.state = .drawing
            game.currentRoundID = pick.roundID
            game.choices = nil
            patch(&game)
            self.game = game
            changed()
            return RemotePickedWord(
                roundID: pick.roundID,
                roundNumber: game.turnNumber,
                difficulty: pick.choice,
                word: word,
                points: points
            )
        }
    }

    func submitDrawing(
        user: UUID,
        roundID: UUID,
        assetID: UUID,
        operation: SyncClientOperation
    ) throws -> RemoteSubmitDrawingResult {
        try runOperation(user, operation, request: ["submit_drawing", roundID.uuidString, assetID.uuidString]) {
            let index = try requireRound(roundID)
            var round = rounds[index]
            guard round.drawer == user else { throw Self.fail("42501", "only the drawer can send the drawing") }
            guard round.drawingAssetID == nil else {
                throw Self.fail("23505", "the drawing for this round was already sent")
            }
            guard let asset = assets[assetID], asset.owner == user, asset.roundID == roundID, !asset.queuedForDelete else {
                throw Self.fail("23514", "game drawing asset is not usable")
            }
            if rounds.contains(where: { $0.drawingAssetID == assetID }) {
                throw Self.fail(
                    "23505",
                    "duplicate key value violates unique constraint \"game_moves_drawing_media_asset_id_unique_idx\""
                )
            }
            let wasDrawing = round.state == .drawing
            round.drawingAssetID = assetID
            round.submittedAt = now
            if wasDrawing {
                round.state = .guessing
            }
            rounds[index] = round
            if wasDrawing, var game {
                game.state = .guessing
                game.turnUser = round.guesser
                game.turnStartedAt = now
                patch(&game)
                self.game = game
            }
            changed()
            return RemoteSubmitDrawingResult(roundID: roundID, roundState: round.state, drawingSubmittedAt: now)
        }
    }

    func markSeen(user: UUID, roundID: UUID) throws -> RemoteMarkSeenResult {
        let index = try requireRound(roundID)
        var round = rounds[index]
        guard round.guesser == user else { throw Self.fail("42501", "only the guesser can see this drawing") }
        guard !round.state.isFinished, round.firstSeenAt == nil else {
            return RemoteMarkSeenResult(guesserFirstSeenAt: round.firstSeenAt)
        }
        round.firstSeenAt = now
        rounds[index] = round
        changed()
        return RemoteMarkSeenResult(guesserFirstSeenAt: now)
    }

    static let maxStoredSolveMs = 30 * 24 * 60 * 60 * 1_000

    func submitGuess( // swiftlint:disable:this function_parameter_count
        user: UUID,
        roundID: UUID,
        guess rawGuess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation: SyncClientOperation
    ) throws -> RemoteGuessResult {
        let guess = Self.normalizeWordText(rawGuess)
        guard !guess.isEmpty, guess.count <= 40 else { throw Self.fail("23514", "guess must be 1 to 40 characters") }
        if let speedBonus, !(0...2).contains(speedBonus) {
            throw Self.fail("23514", "speed bonus must be 0, 1, or 2")
        }
        if let solveMs, solveMs < 0 {
            throw Self.fail("23514", "solve time must be a number of milliseconds from 0 up")
        }
        if let hintsUsed, hintsUsed < 0 {
            throw Self.fail("23514", "hints used must be a whole number from 0 up")
        }
        let request = [
            "submit_guess", roundID.uuidString, guess,
            speedBonus.map { "\($0)" } ?? "null", solveMs.map { "\($0)" } ?? "null",
            hintsUsed.map { "\($0)" } ?? "null",
        ]
        return try runOperation(user, operation, request: request) {
            let index = try requireRound(roundID)
            var round = rounds[index]
            guard round.guesser == user else { throw Self.fail("42501", "only the guesser can guess") }
            guard !round.state.isFinished else { throw Self.fail("23514", "this round is already finished") }
            let correct = guess == round.word
            // A hint can reveal at most all letters but one.
            if correct, let hintsUsed, hintsUsed > round.word.filter({ $0 != " " }).count - 1 {
                throw Self.fail("23514", "hints used is more than the word allows")
            }
            let isFirstAttempt = round.attempts.isEmpty
            let attempt = RemoteDrawAndGuessAttempt(id: UUID(), userID: user, text: guess, correct: correct, createdAt: now)
            round.attempts.append(attempt)
            guard correct else {
                rounds[index] = round
                changed()
                return RemoteGuessResult(
                    guessID: attempt.id,
                    correct: false,
                    roundState: round.state,
                    points: 0,
                    speedBonus: 0,
                    firstTryBonus: 0,
                    hintsUsed: 0,
                    personalBest: false,
                    solveMs: nil,
                    createdAt: now
                )
            }
            let hints = hintsUsed ?? 0
            let scored = scoreSolve(round)
            let bonus = hints > 0 ? 0 : (speedBonus ?? scored.bonus)
            let firstTry = hints == 0 && isFirstAttempt ? 1 : 0
            let storedSolveMs = solveMs.map { min($0, Self.maxStoredSolveMs) } ?? scored.solveMs
            let best = hints == 0 && storedSolveMs.map { isPersonalBest(guesser: user, solveMs: $0) } == true
            round.state = .solved
            round.endedAt = now
            round.solveMs = storedSolveMs
            round.speedBonus = bonus
            round.firstTryBonus = firstTry
            round.hintsUsed = hints
            round.personalBest = best
            rounds[index] = round
            if var game {
                game.points[round.drawer, default: 0] += round.points
                game.points[user, default: 0] += round.points + bonus + firstTry
                game.shared += round.points
                beginTurn(&game, drawer: user)
                self.game = game
            }
            changed()
            return RemoteGuessResult(
                guessID: attempt.id,
                correct: true,
                roundState: .solved,
                points: round.points,
                speedBonus: bonus,
                firstTryBonus: firstTry,
                hintsUsed: hints,
                personalBest: best,
                solveMs: storedSolveMs,
                createdAt: now
            )
        }
    }

    /// `scoreSolve`: 2 within 15 seconds of the first look, 1 within 30, else 0.
    private func scoreSolve(_ round: Round) -> (bonus: Int, solveMs: Int?) {
        guard let seen = round.firstSeenAt else { return (0, nil) }
        let solveMs = max(0, Int(now.timeIntervalSince(seen) * 1_000))
        return (solveMs <= 15_000 ? 2 : solveMs <= 30_000 ? 1 : 0, solveMs)
    }

    /// `isPersonalBest`: faster than every earlier hint-free solve by the guesser, and there is one.
    private func isPersonalBest(guesser: UUID, solveMs: Int) -> Bool {
        let earlier = rounds.filter {
            $0.guesser == guesser && $0.state == .solved && $0.hintsUsed == 0 && $0.solveMs != nil
        }
        return !earlier.isEmpty && earlier.allSatisfy { solveMs < ($0.solveMs ?? 0) }
    }

    func giveUp(user: UUID, roundID: UUID, operation: SyncClientOperation) throws -> RemoteGiveUpResult {
        try runOperation(user, operation, request: ["give_up_round", roundID.uuidString]) {
            let index = try requireRound(roundID)
            var round = rounds[index]
            guard round.guesser == user else { throw Self.fail("42501", "only the guesser can give up") }
            guard !round.state.isFinished else { throw Self.fail("23514", "this round is already finished") }
            round.state = .missed
            round.endedAt = now
            rounds[index] = round
            if var game {
                beginTurn(&game, drawer: user)
                self.game = game
            }
            changed()
            return RemoteGiveUpResult(roundID: roundID, roundState: .missed)
        }
    }

    // MARK: - After the round

    /// `mark_round_result_seen`: the first time wins, for the caller's own role.
    func markResultSeen(user: UUID, roundID: UUID) throws -> RemoteResultSeenResult {
        let index = try requireRound(roundID)
        var round = rounds[index]
        guard round.state.isFinished else { throw Self.fail("23514", "the round is not finished yet") }
        let seenAt: Date
        var isFirstTime = false
        if round.drawer == user {
            isFirstTime = round.drawerSeenAt == nil
            seenAt = round.drawerSeenAt ?? now
            round.drawerSeenAt = seenAt
        } else if round.guesser == user {
            isFirstTime = round.guesserSeenAt == nil
            seenAt = round.guesserSeenAt ?? now
            round.guesserSeenAt = seenAt
        } else {
            throw Self.fail("42501", "only the drawer or the guesser can see this result")
        }
        if isFirstTime {
            rounds[index] = round
            changed()
        }
        return RemoteResultSeenResult(roundID: roundID, resultSeenAt: seenAt)
    }

    /// `set_round_reaction`: the guesser's reaction to a finished round. The last write wins.
    func setReaction(user: UUID, roundID: UUID, reaction: DrawAndGuessReaction?) throws -> RemoteReactionResult {
        let index = try requireRound(roundID)
        guard rounds[index].guesser == user else { throw Self.fail("42501", "only the guesser can react") }
        guard rounds[index].state.isFinished else { throw Self.fail("23514", "the round is not finished yet") }
        if rounds[index].reaction != reaction {
            rounds[index].reaction = reaction
            changed()
        }
        return RemoteReactionResult(roundID: roundID, guesserReaction: reaction)
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
