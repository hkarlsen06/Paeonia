import Foundation

/// What an emoji reaction can be on. The raw values are the server's `target_kind`
/// (`REACTION_TARGET_KINDS` in `backend/convex/lib/validators.ts`).
nonisolated enum ReactionTargetKind: String, Codable, CaseIterable, Sendable {
    case dailyAnswer = "daily_answer"
    case threadMessage = "thread_message"
    case story
    case memory
    case widgetDrawing = "widget_drawing"
    case drawAndGuessRound = "draw_and_guess_round"
    case exquisiteCorpseFigure = "exquisite_corpse_figure"
    case storyChainStory = "story_chain_story"
}

/// One thing a reaction can be on: a story, a memory, a drawing, a finished game creation, or an
/// answer or message in a question's chat.
nonisolated struct ReactionTarget: Hashable, Sendable {
    let kind: ReactionTargetKind
    let id: UUID

    static func story(_ id: UUID) -> Self { Self(kind: .story, id: id) }
    static func memory(_ id: UUID) -> Self { Self(kind: .memory, id: id) }
    /// A saved drawing on the widget, named by its revision id.
    static func widgetDrawing(_ revisionID: UUID) -> Self { Self(kind: .widgetDrawing, id: revisionID) }
    static func drawAndGuessRound(_ id: UUID) -> Self { Self(kind: .drawAndGuessRound, id: id) }
    static func exquisiteCorpseFigure(_ id: UUID) -> Self { Self(kind: .exquisiteCorpseFigure, id: id) }
    static func storyChainStory(_ id: UUID) -> Self { Self(kind: .storyChainStory, id: id) }
    static func dailyAnswer(_ id: UUID) -> Self { Self(kind: .dailyAnswer, id: id) }
    static func threadMessage(_ id: UUID) -> Self { Self(kind: .threadMessage, id: id) }
}

/// One person's emoji reaction to a thing. Each person has at most one on each.
nonisolated struct EmojiReaction: Codable, Equatable, Hashable, Sendable {
    let userID: UUID
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case emoji
    }
}

/// A reaction with the thing it is on, as `reactions:get_reactions` sends and the cache keeps it.
nonisolated struct ReactionRow: Codable, Equatable, Hashable, Sendable {
    let target: ReactionTarget
    let reaction: EmojiReaction

    init(target: ReactionTarget, reaction: EmojiReaction) {
        self.target = target
        self.reaction = reaction
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "target_kind"
        case id = "target_id"
        case userID = "user_id"
        case emoji
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = ReactionTarget(
            kind: try container.decode(ReactionTargetKind.self, forKey: .kind),
            id: try container.decode(UUID.self, forKey: .id)
        )
        reaction = EmojiReaction(
            userID: try container.decode(UUID.self, forKey: .userID),
            emoji: try container.decode(String.self, forKey: .emoji)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.kind, forKey: .kind)
        try container.encode(target.id, forKey: .id)
        try container.encode(reaction.userID, forKey: .userID)
        try container.encode(reaction.emoji, forKey: .emoji)
    }
}

/// The result of `reactions:get_reactions`.
nonisolated struct RemoteReactions: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let reactions: [ReactionRow]

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case reactions
    }
}

/// Who is who, for the words that say who reacted.
nonisolated struct ReactionParticipants: Equatable, Sendable {
    let currentUserID: UUID?
    let partnerName: String
}
