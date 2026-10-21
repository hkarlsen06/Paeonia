import Foundation

/// The favorites backend functions (`backend/convex/favorites.ts`).
nonisolated protocol FavoritesGateway: Sendable {
    /// Saves or unsaves an item for this person. The server sets the given value, so a
    /// retry changes nothing. The partner is never told.
    func setFavorite(_ target: FavoriteTarget, favorited: Bool) async throws
    /// This person's favorites, newest first, as ids only.
    func listFavorites() async throws -> [FavoriteRef]
    /// What the list shows for these favorites, in the same order. An item that is gone is left out.
    func summaries(of targets: [FavoriteTarget]) async throws -> [FavoriteSummary]
}

nonisolated struct LiveFavoritesGateway: FavoritesGateway {
    let client: PaeoniaConvexClient

    func setFavorite(_ target: FavoriteTarget, favorited: Bool) async throws {
        try await client.mutation(
            "favorites:set_favorite",
            args: SetFavoriteRequest(target: target, favorited: favorited)
        )
    }

    func listFavorites() async throws -> [FavoriteRef] {
        try await client.query("favorites:list_favorites")
    }

    func summaries(of targets: [FavoriteTarget]) async throws -> [FavoriteSummary] {
        try await client.query("favorites:get_favorite_summaries", args: SummariesRequest(targets: targets))
    }
}

nonisolated private struct SetFavoriteRequest: Encodable {
    let target: FavoriteTarget
    let favorited: Bool

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case targetID = "p_target_id"
        case favorited = "p_favorited"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.kind, forKey: .kind)
        try container.encode(target.id, forKey: .targetID)
        try container.encode(favorited, forKey: .favorited)
    }
}

nonisolated private struct SummariesRequest: Encodable {
    let targets: [FavoriteTarget]

    enum CodingKeys: String, CodingKey {
        case items = "p_items"
    }

    private struct Item: Encodable {
        let kind: FavoriteKind
        let targetID: UUID

        enum CodingKeys: String, CodingKey {
            case kind
            case targetID = "target_id"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targets.map { Item(kind: $0.kind, targetID: $0.id) }, forKey: .items)
    }
}

// The protocol is async, and this stand-in fails at once.
// swiftlint:disable async_without_await

/// Used when the build has no Convex URL, so every call fails and the screens show what is cached.
nonisolated struct UnavailableFavoritesGateway: FavoritesGateway {
    struct Unavailable: Error {}

    func setFavorite(_: FavoriteTarget, favorited _: Bool) async throws {
        throw Unavailable()
    }

    func listFavorites() async throws -> [FavoriteRef] {
        throw Unavailable()
    }

    func summaries(of _: [FavoriteTarget]) async throws -> [FavoriteSummary] {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await
