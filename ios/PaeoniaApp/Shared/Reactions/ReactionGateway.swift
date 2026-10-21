import Foundation

/// The server call every reaction goes through (`backend/convex/reactions.ts`).
nonisolated protocol ReactionGateway: Sendable {
    /// Sets the user's reaction to `target`, or takes it back with a nil `emoji`. The same call
    /// twice changes nothing.
    func setReaction(_ emoji: String?, on target: ReactionTarget) async throws
}

nonisolated struct LiveReactionGateway: ReactionGateway {
    /// Nil uses the app's shared client when a reaction is sent.
    private let client: PaeoniaConvexClient?

    init(client: PaeoniaConvexClient? = nil) {
        self.client = client
    }

    func setReaction(_ emoji: String?, on target: ReactionTarget) async throws {
        let client = try client ?? PaeoniaConvexClientProvider.shared.client()
        try await client.mutation("reactions:set_reaction", args: SetReactionRequest(target: target, emoji: emoji))
    }
}

nonisolated private struct SetReactionRequest: Encodable {
    let target: ReactionTarget
    /// Nil takes the reaction back.
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case targetID = "p_target_id"
        case emoji = "p_emoji"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.kind, forKey: .kind)
        try container.encode(target.id.uuidString.lowercased(), forKey: .targetID)
        // The server needs the key, with null to take the reaction back.
        try container.encode(emoji, forKey: .emoji)
    }
}
