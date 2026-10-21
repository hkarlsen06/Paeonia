import Foundation

// What the Exquisite corpse screens read. Backend functions are
// `exquisiteCorpse:get_exquisite_corpse`, `submit_exquisite_corpse_part` and
// `get_exquisite_corpse_history`. The state is cached as JSON, so the types
// encode as they decode.

/// An idea from the couple's list, such as "a grandma". Ids are text such as
/// `head-grandma`, not UUIDs, because the lists are written by hand.
nonisolated struct RemoteExquisiteCorpseIdea: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let text: String
}

nonisolated struct RemoteExquisiteCorpsePart: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// 0 for the head, 1 for the body and 2 for the legs.
    let partIndex: Int
    let drawerUserID: UUID
    let createdAt: Date
    /// The bottom of the part, clipped on the drawer's phone. Head and body only.
    /// Both partners may read it as soon as the part is sent.
    let stripMediaAssetID: UUID?
    /// Nil until the figure is finished, unless this person drew the part.
    let drawingMediaAssetID: UUID?
    /// Hidden from the partner until the figure is finished.
    let idea: RemoteExquisiteCorpseIdea?

    enum CodingKeys: String, CodingKey {
        case id
        case partIndex = "part_index"
        case drawerUserID = "drawer_user_id"
        case createdAt = "created_at"
        case stripMediaAssetID = "strip_media_asset_id"
        case drawingMediaAssetID = "drawing_media_asset_id"
        case idea
    }
}

nonisolated extension RemoteExquisiteCorpsePart {
    var kind: ExquisiteCorpsePartKind? {
        ExquisiteCorpsePartKind(rawValue: partIndex)
    }
}

nonisolated struct RemoteExquisiteCorpseFigure: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Counts up from 1 for the couple.
    let number: Int
    /// Draws the head and the legs. The partner draws the body.
    let starterUserID: UUID
    let createdAt: Date
    let finishedAt: Date?
    /// When this person moved past the reveal. The partner's is never sent.
    let myRevealSeenAt: Date?
    /// By part index. Only the parts this person may see.
    var parts: [RemoteExquisiteCorpsePart]

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case starterUserID = "starter_user_id"
        case createdAt = "created_at"
        case finishedAt = "finished_at"
        case myRevealSeenAt = "my_reveal_seen_at"
        case parts
    }
}

nonisolated extension RemoteExquisiteCorpseFigure {
    var isFinished: Bool {
        finishedAt != nil
    }

    func part(at index: Int) -> RemoteExquisiteCorpsePart? {
        parts.first { $0.partIndex == index }
    }
}

nonisolated struct RemoteExquisiteCorpseGame: Codable, Equatable, Sendable {
    let id: UUID
    let turnUserID: UUID
    let turnStartedAt: Date
    /// The figure in progress. Nil between figures, when the next head starts a new one.
    let figureID: UUID?
    /// Of the figure in progress, or of the next one when `figureID` is nil.
    let figureNumber: Int
    /// The part the turn is about: 0, 1 or 2.
    let partIndex: Int
    let figuresFinished: Int
    let version: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case turnUserID = "turn_user_id"
        case turnStartedAt = "turn_started_at"
        case figureID = "figure_id"
        case figureNumber = "figure_number"
        case partIndex = "part_index"
        case figuresFinished = "figures_finished"
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `exquisiteCorpse:get_exquisite_corpse`: everything the game screens show.
nonisolated struct RemoteExquisiteCorpseState: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// The server's data epoch (`PAEONIA_DATA_EPOCH`). It changes only after a backup
    /// restore or a hand edit of the games, and then the server's copy wins.
    let dataEpoch: String
    let game: RemoteExquisiteCorpseGame?
    var currentFigure: RemoteExquisiteCorpseFigure?
    /// Finished figures, newest first, at most 10.
    var recentFigures: [RemoteExquisiteCorpseFigure]
    /// The deck for the part this person draws next. Empty when it is not their turn.
    let ideas: [RemoteExquisiteCorpseIdea]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case dataEpoch = "data_epoch"
        case game
        case currentFigure = "current_figure"
        case recentFigures = "recent_figures"
        case ideas
    }
}

/// `exquisiteCorpse:get_exquisite_corpse_history`: one page of "Our creatures".
nonisolated struct RemoteExquisiteCorpseHistoryPage: Codable, Equatable, Sendable {
    /// Finished figures, newest first, with every part.
    let figures: [RemoteExquisiteCorpseFigure]
    /// Ask for this figure number as `before` to get the next page. Nil on the last page.
    let nextBeforeFigureNumber: Int?

    enum CodingKeys: String, CodingKey {
        case figures
        case nextBeforeFigureNumber = "next_before_figure_number"
    }
}

/// `exquisiteCorpse:submit_exquisite_corpse_part`.
nonisolated struct RemoteExquisiteCorpseSubmitPartResult: Decodable, Equatable, Sendable {
    let figureID: UUID
    let partID: UUID
    let partIndex: Int
    /// The legs were the last part.
    let figureFinished: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case figureID = "figure_id"
        case partID = "part_id"
        case partIndex = "part_index"
        case figureFinished = "figure_finished"
        case createdAt = "created_at"
    }
}

/// `exquisiteCorpse:ensure_exquisite_corpse_game`.
nonisolated struct RemoteExquisiteCorpseEnsureResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    /// False when the couple's game already existed.
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case created
    }
}

/// `exquisiteCorpse:mark_exquisite_corpse_reveal_seen`.
nonisolated struct RemoteExquisiteCorpseRevealSeenResult: Decodable, Equatable, Sendable {
    let figureID: UUID
    /// The first time this person moved past the reveal, also on a repeat call.
    let revealSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case figureID = "figure_id"
        case revealSeenAt = "reveal_seen_at"
    }
}
