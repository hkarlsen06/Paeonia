import Foundation

/// The board game backend functions (`backend/convex/boardGames.ts`). Moves and
/// rematches take a client operation, so a retry after a lost answer is safe:
/// the server runs each operation id once and answers a replay from its record.
nonisolated protocol BoardGamesGateway: Sendable {
    /// One-shot read of what the live feed follows.
    func loadBoardGames() async throws -> RemoteBoardGames
    func loadMarks() async throws -> RemoteBoardGameMarks
    /// One page of finished games of this kind, newest first. Pass the page's
    /// `nextBeforeGameNumber` for the next one.
    func loadHistory(_ kind: GameKind, beforeGameNumber: Int?, limit: Int) async throws -> RemoteBoardGameHistoryPage
    /// Gets or creates the couple's game of this kind. The caller starts a new one.
    func ensureGame(_ kind: GameKind) async throws -> RemoteBoardGame
    func makeMove(_ payload: BoardGameMovePayload, operation: SyncClientOperation) async throws -> RemoteBoardGame
    func startRematch(
        _ payload: BoardGameRematchPayload,
        operation: SyncClientOperation
    ) async throws -> RemoteBoardGame
    /// Saves the caller's mark (`PKDrawing` data), or removes it with nil. Returns
    /// when it was saved, and nil after a removal. The last write wins, so a retry
    /// is safe.
    func setMark(_ data: Data?) async throws -> Date?
}

nonisolated struct LiveBoardGamesGateway: BoardGamesGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func loadBoardGames() async throws -> RemoteBoardGames {
        try await client.query("boardGames:get_board_games")
    }

    func loadMarks() async throws -> RemoteBoardGameMarks {
        try await client.query("boardGames:get_board_game_marks")
    }

    func loadHistory(_ kind: GameKind, beforeGameNumber: Int?, limit: Int) async throws -> RemoteBoardGameHistoryPage {
        try await client.query(
            "boardGames:get_board_game_history",
            args: HistoryRequest(kind: kind, beforeGameNumber: beforeGameNumber, limit: limit)
        )
    }

    func ensureGame(_ kind: GameKind) async throws -> RemoteBoardGame {
        try await client.mutation("boardGames:ensure_board_game", args: EnsureGameRequest(kind: kind))
    }

    func makeMove(_ payload: BoardGameMovePayload, operation: SyncClientOperation) async throws -> RemoteBoardGame {
        try await client.mutation(
            "boardGames:make_move",
            args: MakeMoveRequest(payload: payload, operation: operation)
        )
    }

    func startRematch(
        _ payload: BoardGameRematchPayload,
        operation: SyncClientOperation
    ) async throws -> RemoteBoardGame {
        try await client.mutation(
            "boardGames:start_rematch",
            args: StartRematchRequest(payload: payload, operation: operation)
        )
    }

    func setMark(_ data: Data?) async throws -> Date? {
        let saved: SavedMark? = try await client.mutation(
            "boardGames:set_board_game_mark",
            args: SetMarkRequest(drawing: data?.base64EncodedString())
        )
        return saved?.updatedAt
    }
}

// MARK: - Request bodies

nonisolated private struct EnsureGameRequest: Encodable {
    let kind: GameKind

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
    }
}

nonisolated private struct HistoryRequest: Encodable {
    let kind: GameKind
    let beforeGameNumber: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case beforeGameNumber = "p_before_game_number"
        case limit = "p_limit"
    }
}

nonisolated private struct MakeMoveRequest: Encodable {
    let gameID: UUID
    let expectedVersion: Int
    let move: Int
    /// Only the first move of a game carries one, so the key is left out otherwise.
    let stake: String?
    /// Ludo only, and only on a player's first move of a game.
    let ludoColor: LudoColor?
    let operation: GameClientOperationFields

    init(payload: BoardGameMovePayload, operation: SyncClientOperation) {
        gameID = payload.gameID
        expectedVersion = payload.expectedVersion
        move = payload.move
        stake = payload.stake
        ludoColor = payload.ludoColor
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case expectedVersion = "p_expected_version"
        case move = "p_move"
        case stake = "p_stake"
        case ludoColor = "p_ludo_color"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameID, forKey: .gameID)
        try container.encode(expectedVersion, forKey: .expectedVersion)
        try container.encode(move, forKey: .move)
        try container.encodeIfPresent(stake, forKey: .stake)
        try container.encodeIfPresent(ludoColor, forKey: .ludoColor)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct StartRematchRequest: Encodable {
    let gameID: UUID
    let expectedVersion: Int
    let operation: GameClientOperationFields

    init(payload: BoardGameRematchPayload, operation: SyncClientOperation) {
        gameID = payload.gameID
        expectedVersion = payload.expectedVersion
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case expectedVersion = "p_expected_version"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameID, forKey: .gameID)
        try container.encode(expectedVersion, forKey: .expectedVersion)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct SetMarkRequest: Encodable {
    /// Base64 `PKDrawing` data. Nil removes the mark, so the key is sent as null.
    let drawing: String?

    enum CodingKeys: String, CodingKey {
        case drawing = "p_drawing"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(drawing, forKey: .drawing)
    }
}

nonisolated private struct SavedMark: Decodable {
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
    }
}

// The protocol is async, and this stand-in fails at once.
// swiftlint:disable async_without_await

/// Used when the build has no Convex URL, so every call fails and the screens
/// show what is cached.
nonisolated struct UnavailableBoardGamesGateway: BoardGamesGateway {
    struct Unavailable: Error {}

    func loadBoardGames() async throws -> RemoteBoardGames {
        throw Unavailable()
    }

    func loadMarks() async throws -> RemoteBoardGameMarks {
        throw Unavailable()
    }

    func loadHistory(_: GameKind, beforeGameNumber _: Int?, limit _: Int) async throws -> RemoteBoardGameHistoryPage {
        throw Unavailable()
    }

    func ensureGame(_: GameKind) async throws -> RemoteBoardGame {
        throw Unavailable()
    }

    func makeMove(_: BoardGameMovePayload, operation _: SyncClientOperation) async throws -> RemoteBoardGame {
        throw Unavailable()
    }

    func startRematch(_: BoardGameRematchPayload, operation _: SyncClientOperation) async throws -> RemoteBoardGame {
        throw Unavailable()
    }

    func setMark(_: Data?) async throws -> Date? {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await
