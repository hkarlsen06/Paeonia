import Foundation

nonisolated enum MindMeldGameState: String, Codable, Sendable {
    case playing
    case melded
    case ended
}

nonisolated enum MindMeldEndReason: String, Codable, Sendable {
    /// Round 10 was revealed without a match.
    case rounds
    /// A partner started over.
    case restart
}

nonisolated enum MindMeldRoundState: String, Codable, Sendable {
    case open
    case revealed
}

nonisolated enum MindMeldOutcome: String, Codable, Sendable {
    case match
    /// Almost the same word. A partner can count it as a match.
    case near
    case miss
}

nonisolated struct RemoteMindMeldRound: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundNumber: Int
    let state: MindMeldRoundState
    /// Set when the round is revealed.
    let outcome: MindMeldOutcome?
    /// The partner who counted a near miss as a match.
    var countedByUserID: UUID?
    var myWord: String?
    let myLockedAt: Date?
    let partnerLocked: Bool
    let partnerLockedAt: Date?
    /// Only sent for a revealed round.
    let partnerWord: String?
    let revealedAt: Date?
    let myRevealSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roundNumber = "round_number"
        case state
        case outcome
        case countedByUserID = "counted_by_user_id"
        case myWord = "my_word"
        case myLockedAt = "my_locked_at"
        case partnerLocked = "partner_locked"
        case partnerLockedAt = "partner_locked_at"
        case partnerWord = "partner_word"
        case revealedAt = "revealed_at"
        case myRevealSeenAt = "my_reveal_seen_at"
    }
}

nonisolated struct RemoteMindMeldGame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let gameNumber: Int
    var state: MindMeldGameState
    var endReason: MindMeldEndReason?
    let endedByUserID: UUID?
    let endedAt: Date?
    let maxRounds: Int
    let myEndSeenAt: Date?
    /// Which meld of the couple this game was. Set when the game is melded.
    let meldNumber: Int?
    /// This meld took fewer rounds than every earlier meld.
    let isRecord: Bool
    let createdByUserID: UUID
    let createdAt: Date
    let updatedAt: Date
    let version: Int
    /// Oldest first.
    var rounds: [RemoteMindMeldRound]

    enum CodingKeys: String, CodingKey {
        case id
        case gameNumber = "game_number"
        case state
        case endReason = "end_reason"
        case endedByUserID = "ended_by_user_id"
        case endedAt = "ended_at"
        case maxRounds = "max_rounds"
        case myEndSeenAt = "my_end_seen_at"
        case meldNumber = "meld_number"
        case isRecord = "is_record"
        case createdByUserID = "created_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
        case rounds
    }
}

nonisolated struct RemoteMindMeldStats: Codable, Equatable, Sendable {
    let melds: Int
    let fewestRounds: Int?
    let games: Int

    enum CodingKeys: String, CodingKey {
        case melds
        case fewestRounds = "fewest_rounds"
        case games
    }
}

/// `mindMeld:get_mind_meld`: everything the Mind Meld screens show.
nonisolated struct RemoteMindMeldState: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// The couple's newest game.
    let current: RemoteMindMeldGame?
    /// The game before `current`, while this person has not seen how it ended.
    let previous: RemoteMindMeldGame?
    let stats: RemoteMindMeldStats

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case current
        case previous
        case stats
    }
}

nonisolated extension RemoteMindMeldState {
    /// This state is behind `other`: a lower game number, or the same game at a
    /// lower version, or the same game version that still lists an earlier game
    /// whose ending this person has seen since. A late answer like that must not
    /// replace a newer one.
    func isOlder(than other: RemoteMindMeldState) -> Bool {
        // Game numbers only order the games of one couple. A state from another
        // couple is never older, so it can't win over a purge.
        guard userID == other.userID, coupleID == other.coupleID else { return false }
        // A couple's games never go away, so a read from before the first game
        // is behind one that has it.
        guard let game = current else { return other.current != nil }
        guard let otherGame = other.current else { return false }
        if game.gameNumber != otherGame.gameNumber {
            return game.gameNumber < otherGame.gameNumber
        }
        guard game.id == otherGame.id else { return false }
        if game.version != otherGame.version {
            return game.version < otherGame.version
        }
        // Marking the earlier game's ending as seen does not change `current`.
        return previous != nil && other.previous == nil
    }
}

nonisolated extension RemoteMindMeldGame {
    /// Melded, or ended after round 10 or by a restart.
    var isFinished: Bool { state != .playing }

    var lastRevealedRound: RemoteMindMeldRound? {
        rounds.last { $0.state == .revealed }
    }

    var openRound: RemoteMindMeldRound? {
        rounds.last { $0.state == .open }
    }
}

// MARK: - History

nonisolated struct RemoteMindMeldHistoryRound: Codable, Equatable, Identifiable, Sendable {
    let roundNumber: Int
    let myWord: String
    let partnerWord: String
    let outcome: MindMeldOutcome
    let countedByUserID: UUID?

    var id: Int { roundNumber }

    enum CodingKeys: String, CodingKey {
        case roundNumber = "round_number"
        case myWord = "my_word"
        case partnerWord = "partner_word"
        case outcome
        case countedByUserID = "counted_by_user_id"
    }
}

nonisolated struct RemoteMindMeldHistoryGame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let gameNumber: Int
    let state: MindMeldGameState
    let endReason: MindMeldEndReason?
    let endedByUserID: UUID?
    let createdAt: Date
    let endedAt: Date?
    let meldNumber: Int?
    /// Revealed rounds only, oldest first.
    let rounds: [RemoteMindMeldHistoryRound]

    enum CodingKeys: String, CodingKey {
        case id
        case gameNumber = "game_number"
        case state
        case endReason = "end_reason"
        case endedByUserID = "ended_by_user_id"
        case createdAt = "created_at"
        case endedAt = "ended_at"
        case meldNumber = "meld_number"
        case rounds
    }
}

/// `mindMeld:get_mind_meld_history`: finished games, newest first.
nonisolated struct RemoteMindMeldHistoryPage: Codable, Equatable, Sendable {
    let games: [RemoteMindMeldHistoryGame]
    /// Pass this as the next `p_before_game_number`, or nil on the last page.
    let nextBeforeGameNumber: Int?
    let stats: RemoteMindMeldStats

    enum CodingKeys: String, CodingKey {
        case games
        case nextBeforeGameNumber = "next_before_game_number"
        case stats
    }
}

// MARK: - Mutation results

nonisolated struct RemoteMindMeldLockResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let roundState: MindMeldRoundState
    let outcome: MindMeldOutcome?
    let gameState: MindMeldGameState
    let lockedAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case roundState = "round_state"
        case outcome
        case gameState = "game_state"
        case lockedAt = "locked_at"
    }
}

nonisolated struct RemoteMindMeldCountResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let gameID: UUID
    let gameState: MindMeldGameState

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case gameID = "game_id"
        case gameState = "game_state"
    }
}

nonisolated struct RemoteMindMeldRevealSeenResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let revealSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case revealSeenAt = "reveal_seen_at"
    }
}

nonisolated struct RemoteMindMeldEndSeenResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    let endSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case endSeenAt = "end_seen_at"
    }
}

/// The result of `start_mind_meld_game` and `restart_mind_meld`.
nonisolated struct RemoteMindMeldStartResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case created
    }
}
