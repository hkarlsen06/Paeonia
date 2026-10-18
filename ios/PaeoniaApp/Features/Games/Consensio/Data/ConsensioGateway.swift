import Foundation

/// What the placer puts on the line: a catalog topic, or one they wrote.
nonisolated enum ConsensioTopicChoice: Codable, Equatable, Hashable, Sendable {
    case catalog(RemoteConsensioTopic)
    case own(subject: String, leftEnd: String, rightEnd: String)

    var subject: String {
        switch self {
        case let .catalog(topic): topic.subject
        case let .own(subject, _, _): subject
        }
    }

    var leftEnd: String {
        switch self {
        case let .catalog(topic): topic.leftEnd
        case let .own(_, leftEnd, _): leftEnd
        }
    }

    var rightEnd: String {
        switch self {
        case let .catalog(topic): topic.rightEnd
        case let .own(_, _, rightEnd): rightEnd
        }
    }
}

/// The Consensio backend functions (`backend/convex/consensio.ts`). Presence,
/// invites and settings are in `GamesGateway`. Writes that take a client
/// operation are safe to retry: the server runs each operation id once.
nonisolated protocol ConsensioGateway: Sendable {
    /// One-shot read of what the live feed follows.
    func loadConsensio() async throws -> RemoteConsensioState
    /// Makes the couple's game with this person placing first, or returns the one there is.
    func ensureConsensioGame() async throws -> RemoteConsensioEnsureResult
    func placeConsensioSpot(
        roundID: UUID,
        roundNumber: Int,
        topic: ConsensioTopicChoice,
        spot: Int,
        operation: SyncClientOperation
    ) async throws -> RemoteConsensioRound
    /// Answers with the guessed round, which carries the real spot.
    func guessConsensioSpot(roundID: UUID, guess: Int, operation: SyncClientOperation) async throws
        -> RemoteConsensioRound
    /// The server keeps the first time, so a retry is safe.
    func markConsensioRevealSeen(roundID: UUID) async throws -> RemoteConsensioRevealSeenResult
    /// Guessed rounds, newest first, before `beforeRoundNumber` (nil for the first page).
    func loadConsensioHistory(beforeRoundNumber: Int?, limit: Int) async throws -> RemoteConsensioHistoryPage
}

nonisolated extension LiveGamesGateway: ConsensioGateway {
    func loadConsensio() async throws -> RemoteConsensioState {
        try await client.query("consensio:get_consensio")
    }

    func ensureConsensioGame() async throws -> RemoteConsensioEnsureResult {
        try await client.mutation("consensio:ensure_consensio_game")
    }

    func placeConsensioSpot(
        roundID: UUID,
        roundNumber: Int,
        topic: ConsensioTopicChoice,
        spot: Int,
        operation: SyncClientOperation
    ) async throws -> RemoteConsensioRound {
        try await client.mutation(
            "consensio:place_consensio_spot",
            args: ConsensioPlaceRequest(
                roundID: roundID,
                roundNumber: roundNumber,
                topic: topic,
                spot: spot,
                operation: operation
            )
        )
    }

    func guessConsensioSpot(roundID: UUID, guess: Int, operation: SyncClientOperation) async throws
        -> RemoteConsensioRound {
        try await client.mutation(
            "consensio:guess_consensio_spot",
            args: ConsensioGuessRequest(roundID: roundID, guess: guess, operation: operation)
        )
    }

    func markConsensioRevealSeen(roundID: UUID) async throws -> RemoteConsensioRevealSeenResult {
        try await client.mutation("consensio:mark_consensio_reveal_seen", args: ConsensioRoundRequest(roundID: roundID))
    }

    func loadConsensioHistory(beforeRoundNumber: Int?, limit: Int) async throws -> RemoteConsensioHistoryPage {
        try await client.query(
            "consensio:get_consensio_history",
            args: ConsensioHistoryRequest(beforeRoundNumber: beforeRoundNumber, limit: limit)
        )
    }
}

// The protocol is async, and this stand-in fails at once.
// swiftlint:disable async_without_await
nonisolated extension UnavailableGamesGateway: ConsensioGateway {
    func loadConsensio() async throws -> RemoteConsensioState {
        throw Unavailable()
    }

    func ensureConsensioGame() async throws -> RemoteConsensioEnsureResult {
        throw Unavailable()
    }

    func placeConsensioSpot(
        roundID _: UUID,
        roundNumber _: Int,
        topic _: ConsensioTopicChoice,
        spot _: Int,
        operation _: SyncClientOperation
    ) async throws -> RemoteConsensioRound {
        throw Unavailable()
    }

    func guessConsensioSpot(roundID _: UUID, guess _: Int, operation _: SyncClientOperation) async throws
        -> RemoteConsensioRound {
        throw Unavailable()
    }

    func markConsensioRevealSeen(roundID _: UUID) async throws -> RemoteConsensioRevealSeenResult {
        throw Unavailable()
    }

    func loadConsensioHistory(beforeRoundNumber _: Int?, limit _: Int) async throws -> RemoteConsensioHistoryPage {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await

// MARK: - Request bodies

nonisolated private struct ConsensioRoundRequest: Encodable {
    let roundID: UUID

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
    }
}

nonisolated private struct ConsensioPlaceRequest: Encodable {
    let roundID: UUID
    let roundNumber: Int
    let topic: ConsensioTopicChoice
    /// Sent as a number, as Convex's `v.number()` expects.
    let spot: Int
    let operation: GameClientOperationFields

    init(roundID: UUID, roundNumber: Int, topic: ConsensioTopicChoice, spot: Int, operation: SyncClientOperation) {
        self.roundID = roundID
        self.roundNumber = roundNumber
        self.topic = topic
        self.spot = spot
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case topicID = "p_topic_id"
        case topicLanguage = "p_topic_language"
        case subject = "p_subject"
        case leftEnd = "p_left_end"
        case rightEnd = "p_right_end"
        case spot = "p_spot"
        case roundNumber = "p_round_number"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        switch topic {
        case let .catalog(choice):
            try container.encode(choice.topicID, forKey: .topicID)
            try container.encode(choice.language, forKey: .topicLanguage)
        case let .own(subject, leftEnd, rightEnd):
            try container.encode(subject, forKey: .subject)
            try container.encode(leftEnd, forKey: .leftEnd)
            try container.encode(rightEnd, forKey: .rightEnd)
        }
        try container.encode(Double(spot), forKey: .spot)
        try container.encode(Double(roundNumber), forKey: .roundNumber)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct ConsensioGuessRequest: Encodable {
    let roundID: UUID
    let guess: Int
    let operation: GameClientOperationFields

    init(roundID: UUID, guess: Int, operation: SyncClientOperation) {
        self.roundID = roundID
        self.guess = guess
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case guess = "p_guess"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(Double(guess), forKey: .guess)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct ConsensioHistoryRequest: Encodable {
    /// Nil for the first page, so the key is left out.
    let beforeRoundNumber: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case beforeRoundNumber = "p_before_round_number"
        case limit = "p_limit"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(beforeRoundNumber.map(Double.init), forKey: .beforeRoundNumber)
        try container.encode(Double(limit), forKey: .limit)
    }
}
