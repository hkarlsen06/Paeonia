import Foundation

/// The Mind Meld backend functions (`backend/convex/mindMeld.ts`). Presence,
/// invites and settings are in `GamesGateway`. Writes that take a client
/// operation are safe to retry: the server runs each operation id once.
nonisolated protocol MindMeldGateway: Sendable {
    /// One-shot read of what the live feed follows.
    func loadMindMeld() async throws -> RemoteMindMeldState
    /// Starts a new game at round 1, or returns the game already in play.
    func startMindMeldGame() async throws -> RemoteMindMeldStartResult
    func lockMindMeldWord(
        roundID: UUID,
        word: String,
        operation: SyncClientOperation
    ) async throws -> RemoteMindMeldLockResult
    /// Counts a near miss as a match. Safe to repeat.
    func countMindMeldRound(roundID: UUID) async throws -> RemoteMindMeldCountResult
    /// The server keeps the first time, so a retry is safe.
    func markMindMeldRevealSeen(roundID: UUID) async throws -> RemoteMindMeldRevealSeenResult
    /// The server keeps the first time, so a retry is safe.
    func markMindMeldEndSeen(gameID: UUID) async throws -> RemoteMindMeldEndSeenResult
    /// Ends the game if it is still in play and starts a new one. When the game
    /// already ended, returns the game in play.
    func restartMindMeld(gameID: UUID) async throws -> RemoteMindMeldStartResult
    /// Finished games, newest first, before `beforeGameNumber` (nil for the first page).
    func loadMindMeldHistory(beforeGameNumber: Int?, limit: Int) async throws -> RemoteMindMeldHistoryPage
}

nonisolated extension LiveGamesGateway: MindMeldGateway {
    func loadMindMeld() async throws -> RemoteMindMeldState {
        try await client.query("mindMeld:get_mind_meld")
    }

    func startMindMeldGame() async throws -> RemoteMindMeldStartResult {
        try await client.mutation("mindMeld:start_mind_meld_game")
    }

    func lockMindMeldWord(
        roundID: UUID,
        word: String,
        operation: SyncClientOperation
    ) async throws -> RemoteMindMeldLockResult {
        try await client.mutation(
            "mindMeld:lock_mind_meld_word",
            args: MindMeldLockRequest(roundID: roundID, word: word, operation: operation)
        )
    }

    func countMindMeldRound(roundID: UUID) async throws -> RemoteMindMeldCountResult {
        try await client.mutation("mindMeld:count_mind_meld_round", args: MindMeldRoundRequest(roundID: roundID))
    }

    func markMindMeldRevealSeen(roundID: UUID) async throws -> RemoteMindMeldRevealSeenResult {
        try await client.mutation("mindMeld:mark_mind_meld_reveal_seen", args: MindMeldRoundRequest(roundID: roundID))
    }

    func markMindMeldEndSeen(gameID: UUID) async throws -> RemoteMindMeldEndSeenResult {
        try await client.mutation("mindMeld:mark_mind_meld_end_seen", args: MindMeldGameRequest(gameID: gameID))
    }

    func restartMindMeld(gameID: UUID) async throws -> RemoteMindMeldStartResult {
        try await client.mutation("mindMeld:restart_mind_meld", args: MindMeldGameRequest(gameID: gameID))
    }

    func loadMindMeldHistory(beforeGameNumber: Int?, limit: Int) async throws -> RemoteMindMeldHistoryPage {
        try await client.query(
            "mindMeld:get_mind_meld_history",
            args: MindMeldHistoryRequest(beforeGameNumber: beforeGameNumber, limit: limit)
        )
    }
}

// The protocol is async, and this stand-in fails at once.
// swiftlint:disable async_without_await
nonisolated extension UnavailableGamesGateway: MindMeldGateway {
    func loadMindMeld() async throws -> RemoteMindMeldState {
        throw Unavailable()
    }

    func startMindMeldGame() async throws -> RemoteMindMeldStartResult {
        throw Unavailable()
    }

    func lockMindMeldWord(
        roundID _: UUID,
        word _: String,
        operation _: SyncClientOperation
    ) async throws -> RemoteMindMeldLockResult {
        throw Unavailable()
    }

    func countMindMeldRound(roundID _: UUID) async throws -> RemoteMindMeldCountResult {
        throw Unavailable()
    }

    func markMindMeldRevealSeen(roundID _: UUID) async throws -> RemoteMindMeldRevealSeenResult {
        throw Unavailable()
    }

    func markMindMeldEndSeen(gameID _: UUID) async throws -> RemoteMindMeldEndSeenResult {
        throw Unavailable()
    }

    func restartMindMeld(gameID _: UUID) async throws -> RemoteMindMeldStartResult {
        throw Unavailable()
    }

    func loadMindMeldHistory(beforeGameNumber _: Int?, limit _: Int) async throws -> RemoteMindMeldHistoryPage {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await

// MARK: - Request bodies

nonisolated private struct MindMeldRoundRequest: Encodable {
    let roundID: UUID

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
    }
}

nonisolated private struct MindMeldGameRequest: Encodable {
    let gameID: UUID

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
    }
}

nonisolated private struct MindMeldLockRequest: Encodable {
    let roundID: UUID
    let word: String
    let operation: GameClientOperationFields

    init(roundID: UUID, word: String, operation: SyncClientOperation) {
        self.roundID = roundID
        self.word = word
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case word = "p_word"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(word, forKey: .word)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct MindMeldHistoryRequest: Encodable {
    /// Nil for the first page, so the key is left out.
    let beforeGameNumber: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case beforeGameNumber = "p_before_game_number"
        case limit = "p_limit"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(beforeGameNumber, forKey: .beforeGameNumber)
        try container.encode(limit, forKey: .limit)
    }
}
