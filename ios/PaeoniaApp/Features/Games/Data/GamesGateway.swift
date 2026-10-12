import Foundation

/// The Games backend functions (`backend/convex/games.ts`). Writes that take a
/// client operation are safe to retry: the server runs each operation id once.
nonisolated protocol GamesGateway: Sendable {
    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings
    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult
    /// One-shot read of what the live feed follows.
    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState

    func pickWord(_ pick: GamePickWordPayload, operation: SyncClientOperation) async throws -> RemotePickedWord
    func submitDrawing(
        roundID: UUID,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult
    func markRoundSeen(roundID: UUID) async throws -> RemoteMarkSeenResult
    /// `speedBonus` and `solveMs` are what the player saw on the phone. The server
    /// uses them when present and works them out itself when nil.
    func submitGuess(
        roundID: UUID,
        guess: String,
        speedBonus: Bool?,
        solveMs: Int?,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessResult
    func giveUp(roundID: UUID, operation: SyncClientOperation) async throws -> RemoteGiveUpResult

    func respondSavePrompt(roundID: UUID) async throws
    func saveRoundToMemories(
        roundID: UUID,
        memoryID: UUID,
        mediaAssetID: UUID,
        memoryDate: String
    ) async throws -> RemoteSaveRoundResult

    func sendInvite() async throws -> RemoteInviteResult
    func setPresence(_ isPresent: Bool) async throws
}

nonisolated struct LiveGamesGateway: GamesGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings {
        try await client.mutation(
            "games:set_game_settings",
            args: SetGameSettingsRequest(playStyle: playStyle, language: language)
        )
    }

    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
        try await client.mutation("games:ensure_draw_and_guess_game")
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
        try await client.query("games:get_draw_and_guess")
    }

    func pickWord(_ pick: GamePickWordPayload, operation: SyncClientOperation) async throws -> RemotePickedWord {
        try await client.mutation("games:pick_draw_word", args: PickDrawWordRequest(pick: pick, operation: operation))
    }

    func submitDrawing(
        roundID: UUID,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult {
        try await client.mutation(
            "games:submit_drawing",
            args: SubmitDrawingRequest(roundID: roundID, mediaAssetID: mediaAssetID, operation: operation)
        )
    }

    func markRoundSeen(roundID: UUID) async throws -> RemoteMarkSeenResult {
        try await client.mutation("games:mark_round_seen", args: RoundRequest(roundID: roundID))
    }

    func submitGuess(
        roundID: UUID,
        guess: String,
        speedBonus: Bool?,
        solveMs: Int?,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        try await client.mutation(
            "games:submit_guess",
            args: SubmitGuessRequest(
                roundID: roundID,
                guess: guess,
                speedBonus: speedBonus,
                solveMs: solveMs,
                operation: operation
            )
        )
    }

    func giveUp(roundID: UUID, operation: SyncClientOperation) async throws -> RemoteGiveUpResult {
        try await client.mutation(
            "games:give_up_round",
            args: GiveUpRequest(roundID: roundID, operation: operation)
        )
    }

    func respondSavePrompt(roundID: UUID) async throws {
        try await client.mutation("games:respond_save_prompt", args: RoundRequest(roundID: roundID))
    }

    func saveRoundToMemories(
        roundID: UUID,
        memoryID: UUID,
        mediaAssetID: UUID,
        memoryDate: String
    ) async throws -> RemoteSaveRoundResult {
        try await client.mutation(
            "games:save_round_to_memories",
            args: SaveRoundRequest(
                roundID: roundID,
                memoryID: memoryID,
                mediaAssetID: mediaAssetID,
                memoryDate: memoryDate
            )
        )
    }

    func sendInvite() async throws -> RemoteInviteResult {
        try await client.mutation("games:send_game_invite", args: KindRequest())
    }

    func setPresence(_ isPresent: Bool) async throws {
        try await client.mutation("games:set_game_presence", args: PresenceRequest(isPresent: isPresent))
    }
}

// MARK: - Request bodies

nonisolated private struct SetGameSettingsRequest: Encodable {
    let playStyle: GamePlayStyle
    let language: GameLanguage

    enum CodingKeys: String, CodingKey {
        case playStyle = "p_play_style"
        case language = "p_language"
    }
}

nonisolated private struct RoundRequest: Encodable {
    let roundID: UUID

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
    }
}

nonisolated private struct KindRequest: Encodable {
    let kind = "draw_and_guess"

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
    }
}

nonisolated private struct PresenceRequest: Encodable {
    let kind = "draw_and_guess"
    let isPresent: Bool

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case isPresent = "p_present"
    }
}

nonisolated private struct SaveRoundRequest: Encodable {
    let roundID: UUID
    let memoryID: UUID
    let mediaAssetID: UUID
    let memoryDate: String

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case memoryID = "p_memory_id"
        case mediaAssetID = "p_media_asset_id"
        case memoryDate = "p_memory_date"
    }
}

/// The four fields every client operation write sends.
nonisolated struct GameClientOperationFields: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(_ operation: SyncClientOperation) {
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
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
    let speedBonus: Bool?
    let solveMs: Int?
    let operation: GameClientOperationFields

    init(roundID: UUID, guess: String, speedBonus: Bool?, solveMs: Int?, operation: SyncClientOperation) {
        self.roundID = roundID
        self.guess = guess
        self.speedBonus = speedBonus
        self.solveMs = solveMs
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case guess = "p_guess"
        case speedBonus = "p_speed_bonus"
        case solveMs = "p_solve_ms"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(guess, forKey: .guess)
        try container.encodeIfPresent(speedBonus, forKey: .speedBonus)
        try container.encodeIfPresent(solveMs, forKey: .solveMs)
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
