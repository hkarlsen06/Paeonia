import Foundation

// What "Our drawings" reads: the couple's finished rounds and the records of both
// partners. Backend functions are `drawAndGuess:get_draw_and_guess_history` and
// `drawAndGuess:get_draw_and_guess_records`. Stars are favorites (`FavoritesStore`).

/// One finished round that holds a drawing.
nonisolated struct RemoteDrawAndGuessHistoryRound: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundNumber: Int
    let drawerUserID: UUID
    let guesserUserID: UUID
    /// Lowercase.
    let word: String
    let difficulty: DrawAndGuessDifficulty
    let points: Int
    /// `solved` or `missed`.
    let state: DrawAndGuessRoundState
    let drawingMediaAssetID: UUID
    let solveMs: Int?
    let speedBonus: Int
    let firstTryBonus: Int
    let hintsUsed: Int
    let attemptCount: Int
    let guesserReaction: DrawAndGuessReaction?
    let personalBest: Bool
    let startedAt: Date
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roundNumber = "round_number"
        case drawerUserID = "drawer_user_id"
        case guesserUserID = "guesser_user_id"
        case word
        case difficulty
        case points
        case state
        case drawingMediaAssetID = "drawing_media_asset_id"
        case solveMs = "solve_ms"
        case speedBonus = "speed_bonus"
        case firstTryBonus = "first_try_bonus"
        case hintsUsed = "hints_used"
        case attemptCount = "attempt_count"
        case guesserReaction = "guesser_reaction"
        case personalBest = "personal_best"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

nonisolated extension RemoteDrawAndGuessHistoryRound {
    var isSolved: Bool {
        state == .solved
    }

    /// When the round ended, or started when the end is missing.
    var date: Date {
        endedAt ?? startedAt
    }

    /// Past this, the time says more about the day than about the guess.
    static let longestShownSolveMs = 600_000

    /// The solve time worth showing, or nil when it is missing or too long.
    var shownSolveMs: Int? {
        guard isSolved, let solveMs, solveMs <= Self.longestShownSolveMs else { return nil }
        return solveMs
    }

    /// How many guesses it took, the right one included.
    var tries: Int {
        max(1, attemptCount)
    }

    func isDrawer(_ userID: UUID?) -> Bool {
        userID != nil && drawerUserID == userID
    }
}

/// One page of the history. `nextBeforeRoundNumber` is the cursor for the next
/// page, nil when there are no more rounds.
nonisolated struct RemoteDrawAndGuessHistoryPage: Codable, Equatable, Sendable {
    let rounds: [RemoteDrawAndGuessHistoryRound]
    let nextBeforeRoundNumber: Int?

    enum CodingKeys: String, CodingKey {
        case rounds
        case nextBeforeRoundNumber = "next_before_round_number"
    }
}

/// One partner's numbers. A time is nil when the partner has no solve to count.
nonisolated struct RemoteDrawAndGuessPlayerRecords: Codable, Equatable, Sendable {
    let userID: UUID
    let solves: Int
    let firstTrySolves: Int
    let averageSolveMs: Int?
    let fastestSolveMs: Int?
    let fastestSolveWord: String?
    let drawingsSolved: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case solves
        case firstTrySolves = "first_try_solves"
        case averageSolveMs = "average_solve_ms"
        case fastestSolveMs = "fastest_solve_ms"
        case fastestSolveWord = "fastest_solve_word"
        case drawingsSolved = "drawings_solved"
    }
}

/// `drawAndGuess:get_draw_and_guess_records`. The server lists the caller first.
nonisolated struct RemoteDrawAndGuessRecords: Codable, Equatable, Sendable {
    let partners: [RemoteDrawAndGuessPlayerRecords]

    func records(for userID: UUID?) -> RemoteDrawAndGuessPlayerRecords? {
        guard let userID else { return nil }
        return partners.first { $0.userID == userID }
    }

    /// The partner's numbers: whoever is listed and is not `userID`.
    func partnerRecords(besides userID: UUID?) -> RemoteDrawAndGuessPlayerRecords? {
        guard let userID else { return nil }
        return partners.first { $0.userID != userID }
    }
}

/// What the Games cache keeps for "Our drawings", so the screen opens offline
/// with what was there.
nonisolated struct GamesHistoryCache: Codable, Equatable, Sendable {
    /// The newest rounds, the first page of "All".
    var firstPage: RemoteDrawAndGuessHistoryPage?
    var records: RemoteDrawAndGuessRecords?
}

nonisolated extension GamesLocalDocument {
    mutating func saveHistoryFirstPage(_ page: RemoteDrawAndGuessHistoryPage) {
        var history = drawings ?? GamesHistoryCache()
        history.firstPage = page
        drawings = history
    }

    mutating func saveRecords(_ records: RemoteDrawAndGuessRecords) {
        var history = drawings ?? GamesHistoryCache()
        history.records = records
        drawings = history
    }
}

nonisolated extension RemoteDrawAndGuessState {
    /// The couple has a finished round with a drawing among the rounds the
    /// state carries, so "Our drawings" has something to show.
    var hasFinishedDrawing: Bool {
        ([currentRound].compactMap(\.self) + recentRounds).contains {
            $0.state.isFinished && $0.drawingMediaAssetID != nil
        }
    }
}

/// How the history writes a time and a word.
nonisolated enum DrawAndGuessHistoryFormat {
    /// "24 sec" or "1 min 5 sec". A time under a second reads as 1 second.
    static func duration(ms: Int, width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated) -> String {
        let seconds = max(1, Int((Double(ms) / 1_000).rounded()))
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: width))
    }
}
