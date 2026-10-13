import Foundation

nonisolated enum DrawAndGuessDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case medium
    case hard
    case custom
}

nonisolated enum DrawAndGuessGameState: String, Codable, Sendable {
    case choosingWord = "choosing_word"
    case drawing
    case guessing
}

nonisolated enum DrawAndGuessRoundState: String, Codable, Sendable {
    case drawing
    case guessing
    case solved
    case missed

    var isFinished: Bool {
        self == .solved || self == .missed
    }
}

/// How the guesser reacted to a finished round.
nonisolated enum DrawAndGuessReaction: String, Codable, CaseIterable, Sendable {
    case love
    case laugh
    case wow
}

/// One of the three words offered to the drawer, or the drawer's own pick.
/// Only the drawer whose turn it is receives these.
nonisolated struct RemoteDrawAndGuessChoice: Codable, Equatable, Sendable {
    let difficulty: DrawAndGuessDifficulty
    let wordID: String
    let word: String
    let points: Int

    enum CodingKeys: String, CodingKey {
        case difficulty
        case wordID = "word_id"
        case word
        case points
    }
}

nonisolated struct RemoteDrawAndGuessGame: Codable, Equatable, Sendable {
    let id: UUID
    let kind: String
    let state: DrawAndGuessGameState
    let turnUserID: UUID
    let turnNumber: Int
    let currentRoundID: UUID?
    let sharedPoints: Int
    let myPoints: Int
    let partnerPoints: Int
    let turnStartedAt: Date
    let version: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case state
        case turnUserID = "turn_user_id"
        case turnNumber = "turn_number"
        case currentRoundID = "current_round_id"
        case sharedPoints = "shared_points"
        case myPoints = "my_points"
        case partnerPoints = "partner_points"
        case turnStartedAt = "turn_started_at"
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct RemoteDrawAndGuessAttempt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let text: String
    let correct: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case text
        case correct
        case createdAt = "created_at"
    }
}

nonisolated struct RemoteDrawAndGuessRound: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundNumber: Int
    let drawerUserID: UUID
    let guesserUserID: UUID
    let state: DrawAndGuessRoundState
    let difficulty: DrawAndGuessDifficulty
    /// Lowercase.
    let word: String
    let points: Int
    let drawingMediaAssetID: UUID?
    let drawingSubmittedAt: Date?
    let startedAt: Date
    let guesserFirstSeenAt: Date?
    let endedAt: Date?
    let solveMs: Int?
    /// 0, 1 or 2 points for a fast guess.
    let speedBonus: Int
    /// 1 point for a correct first attempt without hints.
    let firstTryBonus: Int
    /// How many letters the guesser's hints showed.
    let hintsUsed: Int
    /// The guesser's fastest hint-free solve so far, and not their first one.
    let personalBest: Bool
    let guesserReaction: DrawAndGuessReaction?
    /// This person's own private star. The partner's is never sent.
    var starredByMe: Bool
    /// When each partner moved past the result of the finished round.
    let drawerResultSeenAt: Date?
    let guesserResultSeenAt: Date?
    /// Oldest first. The newest 200 when there are more.
    let attempts: [RemoteDrawAndGuessAttempt]
    /// Every attempt of the round, also those past the 200 in `attempts`.
    var attemptCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case roundNumber = "round_number"
        case drawerUserID = "drawer_user_id"
        case guesserUserID = "guesser_user_id"
        case state
        case difficulty
        case word
        case points
        case drawingMediaAssetID = "drawing_media_asset_id"
        case drawingSubmittedAt = "drawing_submitted_at"
        case startedAt = "started_at"
        case guesserFirstSeenAt = "guesser_first_seen_at"
        case endedAt = "ended_at"
        case solveMs = "solve_ms"
        case speedBonus = "speed_bonus"
        case firstTryBonus = "first_try_bonus"
        case hintsUsed = "hints_used"
        case personalBest = "personal_best"
        case guesserReaction = "guesser_reaction"
        case starredByMe = "starred_by_me"
        case drawerResultSeenAt = "drawer_result_seen_at"
        case guesserResultSeenAt = "guesser_result_seen_at"
        case attempts
        case attemptCount = "attempt_count"
    }
}

/// `games:get_draw_and_guess`: everything the Draw & Guess screens show. The
/// server reads no clock, so the presence timestamps are judged on the phone.
nonisolated struct RemoteDrawAndGuessState: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    let settings: RemoteGameSettings?
    let game: RemoteDrawAndGuessGame?
    var currentRound: RemoteDrawAndGuessRound?
    /// Newest first, at most 20.
    var recentRounds: [RemoteDrawAndGuessRound]
    /// Only the drawer whose turn it is, while the game is choosing a word.
    let choices: [RemoteDrawAndGuessChoice]?
    let myLastSeenAt: Date?
    let partnerLastSeenAt: Date?
    let lastInviteAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case settings
        case game
        case currentRound = "current_round"
        case recentRounds = "recent_rounds"
        case choices
        case myLastSeenAt = "my_last_seen_at"
        case partnerLastSeenAt = "partner_last_seen_at"
        case lastInviteAt = "last_invite_at"
    }
}

// MARK: - Mutation results

nonisolated struct RemoteEnsureGameResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case created
    }
}

nonisolated struct RemotePickedWord: Decodable, Equatable, Sendable {
    let roundID: UUID
    let roundNumber: Int
    let difficulty: DrawAndGuessDifficulty
    let word: String
    let points: Int

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case roundNumber = "round_number"
        case difficulty
        case word
        case points
    }
}

nonisolated struct RemoteSubmitDrawingResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let roundState: DrawAndGuessRoundState
    let drawingSubmittedAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case roundState = "round_state"
        case drawingSubmittedAt = "drawing_submitted_at"
    }
}

nonisolated struct RemoteMarkSeenResult: Decodable, Equatable, Sendable {
    let guesserFirstSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case guesserFirstSeenAt = "guesser_first_seen_at"
    }
}

nonisolated struct RemoteGuessResult: Decodable, Equatable, Sendable {
    let guessID: UUID
    let correct: Bool
    let roundState: DrawAndGuessRoundState
    let points: Int
    let speedBonus: Int
    let firstTryBonus: Int
    let hintsUsed: Int
    let personalBest: Bool
    let solveMs: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case guessID = "guess_id"
        case correct
        case roundState = "round_state"
        case points
        case speedBonus = "speed_bonus"
        case firstTryBonus = "first_try_bonus"
        case hintsUsed = "hints_used"
        case personalBest = "personal_best"
        case solveMs = "solve_ms"
        case createdAt = "created_at"
    }
}

nonisolated struct RemoteGiveUpResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let roundState: DrawAndGuessRoundState

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case roundState = "round_state"
    }
}

nonisolated struct RemoteReactionResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let guesserReaction: DrawAndGuessReaction?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case guesserReaction = "guesser_reaction"
    }
}

nonisolated struct RemoteResultSeenResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let resultSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case resultSeenAt = "result_seen_at"
    }
}

nonisolated struct RemoteInviteResult: Decodable, Equatable, Sendable {
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case sentAt = "sent_at"
    }
}
