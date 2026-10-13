import Foundation

/// The backend functions every game shares (`backend/convex/games.ts`). Each game
/// adds its own functions in a protocol of its own, such as `DrawAndGuessGateway`.
/// Writes that take a client operation are safe to retry: the server runs each
/// operation id once.
nonisolated protocol GamesGateway: Sendable {
    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings
    /// One-shot read of what the Games tab shares: the settings, and for each game
    /// who has it open and this person's last invite.
    func loadOverview() async throws -> RemoteGamesOverview
    /// Tells the server this person has the game open (or has left it).
    func setPresence(_ kind: GameKind, isPresent: Bool) async throws
    func sendInvite(_ kind: GameKind) async throws -> RemoteInviteResult
}

nonisolated struct LiveGamesGateway: GamesGateway {
    /// Internal, because each game's gateway extension sends through it.
    let client: PaeoniaConvexClient

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings {
        try await client.mutation(
            "games:set_game_settings",
            args: SetGameSettingsRequest(playStyle: playStyle, language: language)
        )
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        try await client.query("games:get_games_overview")
    }

    func setPresence(_ kind: GameKind, isPresent: Bool) async throws {
        try await client.mutation("games:set_game_presence", args: PresenceRequest(kind: kind, isPresent: isPresent))
    }

    func sendInvite(_ kind: GameKind) async throws -> RemoteInviteResult {
        try await client.mutation("games:send_game_invite", args: KindRequest(kind: kind))
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

nonisolated private struct KindRequest: Encodable {
    let kind: GameKind

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
    }
}

nonisolated private struct PresenceRequest: Encodable {
    let kind: GameKind
    let isPresent: Bool

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case isPresent = "p_present"
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
