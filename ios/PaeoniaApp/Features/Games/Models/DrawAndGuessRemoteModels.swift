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

/// A partner's answer to the save prompt. Only "Not now" is stored. A yes
/// saves the memory instead.
nonisolated enum DrawAndGuessSaveResponse: String, Codable, Sendable {
    case notNow = "not_now"
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
    let speedBonus: Int
    let memoryID: UUID?
    let savedByUserID: UUID?
    let mySaveResponse: DrawAndGuessSaveResponse?
    let partnerSaveResponse: DrawAndGuessSaveResponse?
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
        case memoryID = "memory_id"
        case savedByUserID = "saved_by_user_id"
        case mySaveResponse = "my_save_response"
        case partnerSaveResponse = "partner_save_response"
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
    let currentRound: RemoteDrawAndGuessRound?
    /// Newest first, at most 20.
    let recentRounds: [RemoteDrawAndGuessRound]
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
    let solveMs: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case guessID = "guess_id"
        case correct
        case roundState = "round_state"
        case points
        case speedBonus = "speed_bonus"
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

nonisolated struct RemoteSaveRoundResult: Decodable, Equatable, Sendable {
    let memoryID: UUID
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case created
    }
}

nonisolated struct RemoteInviteResult: Decodable, Equatable, Sendable {
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case sentAt = "sent_at"
    }
}
