import Foundation

extension GameStarSource {
    /// Draw & Guess stars rounds. The server's answer is the cached history list
    /// with the rounds of the game state on top. The state is the freshest answer
    /// for its own rounds, and the list covers the older ones.
    static func drawAndGuess(cache: any GamesCaching) -> GameStarSource {
        GameStarSource(
            operationKind: .setGameRoundStar,
            scope: { "game-star:\($0.uuidString.lowercased())" },
            payload: { roundID, starred, createdAt in
                try JSONEncoder().encode(GameStarPayload(roundID: roundID, starred: starred, createdAt: createdAt))
            },
            queued: { data in
                (try? JSONDecoder().decode(GameStarPayload.self, from: data))
                    .map { (id: $0.roundID, starred: $0.starred) }
            },
            serverStars: { ownerUserID in
                let document = await cache.document(ownerUserID: ownerUserID)
                var stars = Set(document.drawings?.starredRoundIDs ?? [])
                for (roundID, isStarred) in document.state?.starValues ?? [:] {
                    if isStarred { stars.insert(roundID) } else { stars.remove(roundID) }
                }
                return stars
            },
            saveServerStars: { stars, ownerUserID in
                await cache.saveStars(stars, ownerUserID: ownerUserID)
            }
        )
    }
}
