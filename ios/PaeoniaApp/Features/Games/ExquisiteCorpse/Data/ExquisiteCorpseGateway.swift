import Foundation

/// The Exquisite corpse backend functions (`backend/convex/exquisiteCorpse.ts`).
/// Writes that take a client operation are safe to retry: the server runs each
/// operation id once. The reveal seen mark sets a value, so sending
/// them twice changes nothing.
nonisolated protocol ExquisiteCorpseGateway: Sendable {
    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult
    /// One-shot read of what the live feed follows.
    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState
    /// Sends a part whose files are already uploaded. `stripAssetID` is set for the
    /// head and the body and nil for the legs.
    func submitExquisiteCorpsePart(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID: UUID,
        stripAssetID: UUID?,
        operation: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult
    /// This person moved past the finished figure's reveal. The server keeps the
    /// first time.
    func markExquisiteCorpseRevealSeen(figureID: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult
    /// A page of the couple's finished figures, newest first, before
    /// `beforeFigureNumber`. With `starredOnly`, only the figures this person starred.
    func loadExquisiteCorpseHistory(
        starredOnly: Bool,
        beforeFigureNumber: Int?,
        limit: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage
    /// One finished figure by id, also one that is not in a loaded page. Nil when the
    /// couple has no such finished figure.
    func loadExquisiteCorpseFigure(figureID: UUID) async throws -> RemoteExquisiteCorpseFigure?
}

nonisolated struct LiveExquisiteCorpseGateway: ExquisiteCorpseGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult {
        try await client.mutation("exquisiteCorpse:ensure_exquisite_corpse_game")
    }

    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState {
        try await client.query("exquisiteCorpse:get_exquisite_corpse")
    }

    func submitExquisiteCorpsePart(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID: UUID,
        stripAssetID: UUID?,
        operation: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult {
        try await client.mutation(
            "exquisiteCorpse:submit_exquisite_corpse_part",
            args: SubmitPartRequest(
                payload: payload,
                drawingAssetID: drawingAssetID,
                stripAssetID: stripAssetID,
                operation: operation
            )
        )
    }

    func markExquisiteCorpseRevealSeen(figureID: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult {
        try await client.mutation(
            "exquisiteCorpse:mark_exquisite_corpse_reveal_seen",
            args: FigureRequest(figureID: figureID)
        )
    }

    func loadExquisiteCorpseHistory(
        starredOnly: Bool,
        beforeFigureNumber: Int?,
        limit: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage {
        try await client.query(
            "exquisiteCorpse:get_exquisite_corpse_history",
            args: HistoryRequest(starredOnly: starredOnly, beforeFigureNumber: beforeFigureNumber, limit: limit)
        )
    }

    func loadExquisiteCorpseFigure(figureID: UUID) async throws -> RemoteExquisiteCorpseFigure? {
        try await client.query("exquisiteCorpse:get_exquisite_corpse_figure", args: FigureRequest(figureID: figureID))
    }
}

// MARK: - Request bodies

nonisolated private struct SubmitPartRequest: Encodable {
    let gameID: UUID
    let figureID: UUID
    let partID: UUID
    let partIndex: Int
    let drawingAssetID: UUID
    /// Nil for the legs, so the key is left out.
    let stripAssetID: UUID?
    /// Nil when the part has no idea, so the key is left out.
    let ideaID: String?
    let operation: GameClientOperationFields

    init(
        payload: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID: UUID,
        stripAssetID: UUID?,
        operation: SyncClientOperation
    ) {
        gameID = payload.gameID
        figureID = payload.figureID
        partID = payload.partID
        partIndex = payload.partIndex
        self.drawingAssetID = drawingAssetID
        self.stripAssetID = stripAssetID
        ideaID = payload.idea?.id
        self.operation = GameClientOperationFields(operation)
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "p_game_id"
        case figureID = "p_figure_id"
        case partID = "p_part_id"
        case partIndex = "p_part_index"
        case drawingAssetID = "p_drawing_media_asset_id"
        case stripAssetID = "p_strip_media_asset_id"
        case ideaID = "p_idea_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gameID, forKey: .gameID)
        try container.encode(figureID, forKey: .figureID)
        try container.encode(partID, forKey: .partID)
        try container.encode(partIndex, forKey: .partIndex)
        try container.encode(drawingAssetID, forKey: .drawingAssetID)
        try container.encodeIfPresent(stripAssetID, forKey: .stripAssetID)
        try container.encodeIfPresent(ideaID, forKey: .ideaID)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct FigureRequest: Encodable {
    let figureID: UUID

    enum CodingKeys: String, CodingKey {
        case figureID = "p_figure_id"
    }
}

nonisolated private struct HistoryRequest: Encodable {
    let starredOnly: Bool
    /// Nil for the first page, so the key is left out.
    let beforeFigureNumber: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case starredOnly = "p_starred_only"
        case beforeFigureNumber = "p_before_figure_number"
        case limit = "p_limit"
    }
}

// The protocol is async, and this stand-in fails at once.
// swiftlint:disable async_without_await

/// Used when the build has no Convex URL, so every call fails and the screens
/// show what is cached.
nonisolated struct UnavailableExquisiteCorpseGateway: ExquisiteCorpseGateway {
    struct Unavailable: Error {}

    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult {
        throw Unavailable()
    }

    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState {
        throw Unavailable()
    }

    func submitExquisiteCorpsePart(
        _: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID _: UUID,
        stripAssetID _: UUID?,
        operation _: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult {
        throw Unavailable()
    }

    func markExquisiteCorpseRevealSeen(figureID _: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult {
        throw Unavailable()
    }

    func loadExquisiteCorpseHistory(
        starredOnly _: Bool,
        beforeFigureNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage {
        throw Unavailable()
    }

    func loadExquisiteCorpseFigure(figureID _: UUID) async throws -> RemoteExquisiteCorpseFigure? {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await
