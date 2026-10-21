import Foundation

/// What a person can favorite. The raw values are the backend's favorite kinds
/// (`FAVORITE_KINDS` in `backend/convex/lib/validators.ts`). To make a new kind
/// favoritable, add a case here and the backend loader, then put a
/// `FavoriteStarButton` on its screen.
nonisolated enum FavoriteKind: String, Codable, CaseIterable, Sendable {
    /// A daily or topic question. Its id is the question's id, because the question's
    /// page spans every day the question came back.
    case dailyQuestion = "daily_question"
    case dailyAnswer = "daily_answer"
    case widgetDrawing = "widget_drawing"
    case gameRound = "game_round"
    case corpseFigure = "corpse_figure"
    case storyChainStory = "story_chain_story"
}

/// One thing that can be a favorite.
nonisolated struct FavoriteTarget: Hashable, Codable, Sendable {
    let kind: FavoriteKind
    let id: UUID

    static func question(_ id: UUID) -> FavoriteTarget { FavoriteTarget(kind: .dailyQuestion, id: id) }
    static func answer(_ id: UUID) -> FavoriteTarget { FavoriteTarget(kind: .dailyAnswer, id: id) }
    static func widgetDrawing(_ id: UUID) -> FavoriteTarget { FavoriteTarget(kind: .widgetDrawing, id: id) }
    static func gameRound(_ id: UUID) -> FavoriteTarget { FavoriteTarget(kind: .gameRound, id: id) }
    static func corpseFigure(_ id: UUID) -> FavoriteTarget { FavoriteTarget(kind: .corpseFigure, id: id) }
    static func storyChainStory(_ id: UUID) -> FavoriteTarget { FavoriteTarget(kind: .storyChainStory, id: id) }
}

/// A favorite as `favorites:list_favorites` and the phone's cache hold it.
nonisolated struct FavoriteRef: Hashable, Codable, Sendable {
    let target: FavoriteTarget
    let createdAt: Date

    init(target: FavoriteTarget, createdAt: Date) {
        self.target = target
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = FavoriteTarget(
            kind: try container.decode(FavoriteKind.self, forKey: .kind),
            id: try container.decode(UUID.self, forKey: .targetID)
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.kind, forKey: .kind)
        try container.encode(target.id, forKey: .targetID)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case targetID = "target_id"
        case createdAt = "created_at"
    }
}
