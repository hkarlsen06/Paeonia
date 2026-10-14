import Foundation

extension GameStarSource {
    /// Exquisite corpse stars figures. The server's answer is the figures of the
    /// cached game state, and for figures the state no longer carries, the stars
    /// the cache kept from history pages and finished star writes.
    static func exquisiteCorpse(cache: any ExquisiteCorpseCaching) -> GameStarSource {
        GameStarSource(
            operationKind: .exquisiteCorpseStar,
            scope: { "exquisite-corpse-star:\($0.uuidString.lowercased())" },
            payload: { figureID, starred, createdAt in
                try JSONEncoder().encode(
                    ExquisiteCorpseStarPayload(figureID: figureID, starred: starred, createdAt: createdAt)
                )
            },
            queued: { data in
                (try? JSONDecoder().decode(ExquisiteCorpseStarPayload.self, from: data))
                    .map { (id: $0.figureID, starred: $0.starred) }
            },
            serverStars: { ownerUserID in
                let document = await cache.document(ownerUserID: ownerUserID)
                var stars = Set(document.stars.filter(\.value).keys)
                for (figureID, isStarred) in document.state?.starValues ?? [:] {
                    if isStarred { stars.insert(figureID) } else { stars.remove(figureID) }
                }
                return stars
            },
            saveServerStars: { stars, ownerUserID in
                await cache.saveStars(stars, ownerUserID: ownerUserID)
            }
        )
    }
}
