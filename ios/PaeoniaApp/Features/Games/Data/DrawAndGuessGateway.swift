import Foundation

/// The Draw & Guess backend functions (`backend/convex/drawAndGuess.ts`) on top
/// of the shared ones. Writes that take a client operation are safe to retry:
/// the server runs each operation id once.
nonisolated protocol DrawAndGuessGateway: GamesGateway {
    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult
    /// One-shot read of what the live feed follows.
    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState
    /// One round by id, also one that is no longer among the recent rounds. Nil
    /// when the couple has no such round.
    func loadDrawAndGuessRound(roundID: UUID) async throws -> RemoteDrawAndGuessRound?

    func pickWord(_ pick: GamePickWordPayload, operation: SyncClientOperation) async throws -> RemotePickedWord
    func submitDrawing(
        roundID: UUID,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult
    func markRoundSeen(roundID: UUID) async throws -> RemoteMarkSeenResult
    /// `speedBonus` (0, 1 or 2), `solveMs` and `hintsUsed` are what the player saw
    /// on the phone. The server uses them when present and works the speed bonus
    /// and solve time out itself when nil. Any hint sets both bonuses to 0.
    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID: UUID,
        guess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessResult
    func giveUp(roundID: UUID, operation: SyncClientOperation) async throws -> RemoteGiveUpResult

    /// This person moved past the finished round's result. The server keeps the
    /// first time, so a retry is safe.
    func markRoundResultSeen(roundID: UUID) async throws -> RemoteResultSeenResult

    /// A page of the couple's finished rounds with a drawing, newest first, before
    /// `beforeRoundNumber`. With `starredOnly`, only the rounds this person starred.
    func loadDrawAndGuessHistory(
        starredOnly: Bool,
        beforeRoundNumber: Int?,
        limit: Int
    ) async throws -> RemoteDrawAndGuessHistoryPage
    /// One finished round by id, also one that is not in a loaded page. Nil when the
    /// couple has no such finished round.
    func loadDrawAndGuessHistoryRound(roundID: UUID) async throws -> RemoteDrawAndGuessHistoryRound?
    func loadDrawAndGuessRecords() async throws -> RemoteDrawAndGuessRecords
}

nonisolated extension LiveGamesGateway: DrawAndGuessGateway {
    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
        try await client.mutation("drawAndGuess:ensure_draw_and_guess_game")
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
        try await client.query("drawAndGuess:get_draw_and_guess")
    }

    func loadDrawAndGuessRound(roundID: UUID) async throws -> RemoteDrawAndGuessRound? {
        try await client.query("drawAndGuess:get_draw_and_guess_round", args: RoundRequest(roundID: roundID))
    }

    func pickWord(_ pick: GamePickWordPayload, operation: SyncClientOperation) async throws -> RemotePickedWord {
        try await client.mutation(
            "drawAndGuess:pick_draw_word",
            args: PickDrawWordRequest(pick: pick, operation: operation)
        )
    }

    func submitDrawing(
        roundID: UUID,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult {
        try await client.mutation(
            "drawAndGuess:submit_drawing",
            args: SubmitDrawingRequest(roundID: roundID, mediaAssetID: mediaAssetID, operation: operation)
        )
    }

    func markRoundSeen(roundID: UUID) async throws -> RemoteMarkSeenResult {
        try await client.mutation("drawAndGuess:mark_round_seen", args: RoundRequest(roundID: roundID))
    }

    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID: UUID,
        guess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        try await client.mutation(
            "drawAndGuess:submit_guess",
            args: SubmitGuessRequest(
                roundID: roundID,
                guess: guess,
                speedBonus: speedBonus,
                solveMs: solveMs,
                hintsUsed: hintsUsed,
                operation: operation
            )
        )
    }

    func giveUp(roundID: UUID, operation: SyncClientOperation) async throws -> RemoteGiveUpResult {
        try await client.mutation(
            "drawAndGuess:give_up_round",
            args: GiveUpRequest(roundID: roundID, operation: operation)
        )
    }

    func markRoundResultSeen(roundID: UUID) async throws -> RemoteResultSeenResult {
        try await client.mutation("drawAndGuess:mark_round_result_seen", args: RoundRequest(roundID: roundID))
    }

    func loadDrawAndGuessHistory(
        starredOnly: Bool,
        beforeRoundNumber: Int?,
        limit: Int
    ) async throws -> RemoteDrawAndGuessHistoryPage {
        try await client.query(
            "drawAndGuess:get_draw_and_guess_history",
            args: HistoryRequest(starredOnly: starredOnly, beforeRoundNumber: beforeRoundNumber, limit: limit)
        )
    }

    func loadDrawAndGuessHistoryRound(roundID: UUID) async throws -> RemoteDrawAndGuessHistoryRound? {
        try await client.query("drawAndGuess:get_draw_and_guess_history_round", args: RoundRequest(roundID: roundID))
    }

    func loadDrawAndGuessRecords() async throws -> RemoteDrawAndGuessRecords {
        try await client.query("drawAndGuess:get_draw_and_guess_records")
    }
}

// MARK: - Request bodies

nonisolated private struct RoundRequest: Encodable {
    let roundID: UUID

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
    }
}

nonisolated private struct HistoryRequest: Encodable {
    let starredOnly: Bool
    /// Nil for the first page, so the key is left out.
    let beforeRoundNumber: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case starredOnly = "p_starred_only"
        case beforeRoundNumber = "p_before_round_number"
        case limit = "p_limit"
    }
}

nonisolated private struct PickDrawWordRequest: Encodable {
    let gameID: UUID
    let roundID: UUID
    let choice: DrawAndGuessDifficulty
    let customWord: String?
    let wordID: String?
    let operation: GameClientOperationFields

    init(pick: GamePickWordPayload, operation: SyncClientOperation) {
        gameID = pick.gameID
        roundID = pick.roundID
        choice = pick.choice
        customWord = pick.choice == .custom ? pick.word : nil
        wordID = pick.choice == .custom ? nil : pick.wordID
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case roundID = "p_round_id"
        case choice = "p_choice"
        case customWord = "p_custom_word"
        case wordID = "p_word_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameID, forKey: .gameID)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(choice, forKey: .choice)
        try container.encodeIfPresent(customWord, forKey: .customWord)
        try container.encodeIfPresent(wordID, forKey: .wordID)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct SubmitDrawingRequest: Encodable {
    let roundID: UUID
    let mediaAssetID: UUID
    let operation: GameClientOperationFields

    init(roundID: UUID, mediaAssetID: UUID, operation: SyncClientOperation) {
        self.roundID = roundID
        self.mediaAssetID = mediaAssetID
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case mediaAssetID = "p_media_asset_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(mediaAssetID, forKey: .mediaAssetID)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct SubmitGuessRequest: Encodable {
    let roundID: UUID
    let guess: String
    let speedBonus: Int?
    let solveMs: Int?
    let hintsUsed: Int?
    let operation: GameClientOperationFields

    init(
        roundID: UUID,
        guess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation: SyncClientOperation
    ) {
        self.roundID = roundID
        self.guess = guess
        self.speedBonus = speedBonus
        self.solveMs = solveMs
        self.hintsUsed = hintsUsed
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case guess = "p_guess"
        case speedBonus = "p_speed_bonus"
        case solveMs = "p_solve_ms"
        case hintsUsed = "p_hints_used"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(guess, forKey: .guess)
        try container.encodeIfPresent(speedBonus, forKey: .speedBonus)
        try container.encodeIfPresent(solveMs, forKey: .solveMs)
        try container.encodeIfPresent(hintsUsed, forKey: .hintsUsed)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct GiveUpRequest: Encodable {
    let roundID: UUID
    let operation: GameClientOperationFields

    init(roundID: UUID, operation: SyncClientOperation) {
        self.roundID = roundID
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try operation.encode(to: encoder)
    }
}
