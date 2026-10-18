import Foundation

/// One topic the placer can pick: a subject and the two ends of the line.
nonisolated struct RemoteConsensioTopic: Codable, Equatable, Hashable, Sendable {
    let topicID: String
    let language: GameLanguage
    let subject: String
    let leftEnd: String
    let rightEnd: String

    enum CodingKeys: String, CodingKey {
        case topicID = "topic_id"
        case language
        case subject
        case leftEnd = "left_end"
        case rightEnd = "right_end"
    }
}

/// One round: the placer's marker and, once guessed, the partner's guess.
nonisolated struct RemoteConsensioRound: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundNumber: Int
    let placerUserID: UUID
    let guesserUserID: UUID
    /// Nil for a topic the placer wrote.
    let topicID: String?
    let language: GameLanguage?
    let subject: String
    let leftEnd: String
    let rightEnd: String
    /// The real spot, 0 to 100. The guesser gets it only once the round has a guess.
    var spot: Int?
    let placedAt: Date
    var guess: Int?
    var distance: Int?
    var points: Int?
    var guessedAt: Date?
    var myRevealSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roundNumber = "round_number"
        case placerUserID = "placer_user_id"
        case guesserUserID = "guesser_user_id"
        case topicID = "topic_id"
        case language
        case subject
        case leftEnd = "left_end"
        case rightEnd = "right_end"
        case spot
        case placedAt = "placed_at"
        case guess
        case distance
        case points
        case guessedAt = "guessed_at"
        case myRevealSeenAt = "my_reveal_seen_at"
    }
}

nonisolated struct RemoteConsensioGame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Who acts next: the guesser while the newest round has no guess, the next placer after that.
    var turnUserID: UUID
    let turnStartedAt: Date
    /// The next placer's three topics. Empty for the other partner.
    var choices: [RemoteConsensioTopic]
    var sharedPoints: Int
    var roundCount: Int
    let version: Int
    let createdByUserID: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case turnUserID = "turn_user_id"
        case turnStartedAt = "turn_started_at"
        case choices
        case sharedPoints = "shared_points"
        case roundCount = "round_count"
        case version
        case createdByUserID = "created_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `consensio:get_consensio`: everything the Consensio screens show.
nonisolated struct RemoteConsensioState: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// The server's data epoch (`PAEONIA_DATA_EPOCH`). It changes only after a backup
    /// restore or a hand edit of the games, and then the server's copy wins.
    let dataEpoch: String
    /// Nil before the couple's first game.
    let game: RemoteConsensioGame?
    /// The newest round.
    let currentRound: RemoteConsensioRound?
    /// The round before it, so a reveal this person missed still shows.
    let previousRound: RemoteConsensioRound?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case dataEpoch = "data_epoch"
        case game
        case currentRound = "current_round"
        case previousRound = "previous_round"
    }
}

nonisolated extension RemoteConsensioState {
    /// This state is behind `other`: the same game at a lower version, or no game
    /// while the other has one. A late answer like that must not replace a newer one.
    func isOlder(than other: RemoteConsensioState) -> Bool {
        // A state from another person, couple or data epoch is never older, so it
        // can't win over a purge or a restore.
        guard userID == other.userID, coupleID == other.coupleID, dataEpoch == other.dataEpoch else { return false }
        guard let game else { return other.game != nil }
        guard let otherGame = other.game, game.id == otherGame.id else { return false }
        return game.version < otherGame.version
    }
}

// MARK: - History

nonisolated struct RemoteConsensioGuesserRecord: Codable, Equatable, Sendable {
    let guesses: Int
    let spotOns: Int
    /// Rounded to a whole number. Nil before the first guess.
    let averageDistance: Int?

    enum CodingKeys: String, CodingKey {
        case guesses
        case spotOns = "spot_ons"
        case averageDistance = "average_distance"
    }
}

nonisolated struct RemoteConsensioRecords: Codable, Equatable, Sendable {
    let sharedPoints: Int
    /// This person as the guesser.
    let mine: RemoteConsensioGuesserRecord
    let partner: RemoteConsensioGuesserRecord

    enum CodingKeys: String, CodingKey {
        case sharedPoints = "shared_points"
        case mine
        case partner
    }
}

/// `consensio:get_consensio_history`: guessed rounds, newest first.
nonisolated struct RemoteConsensioHistoryPage: Codable, Equatable, Sendable {
    let rounds: [RemoteConsensioRound]
    /// Pass this as the next `p_before_round_number`, or nil on the last page.
    let nextBeforeRoundNumber: Int?
    let records: RemoteConsensioRecords

    enum CodingKeys: String, CodingKey {
        case rounds
        case nextBeforeRoundNumber = "next_before_round_number"
        case records
    }
}

// MARK: - Mutation results

nonisolated struct RemoteConsensioEnsureResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case created
    }
}

nonisolated struct RemoteConsensioRevealSeenResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let revealSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case revealSeenAt = "reveal_seen_at"
    }
}
