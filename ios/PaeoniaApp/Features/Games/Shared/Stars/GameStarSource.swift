import Foundation

/// What `GameStars` needs from one game: how its star write is queued, how to
/// read a queued write back, and where the server's answers are kept. A game
/// builds its source from its own cache, such as `.drawAndGuess(cache:)`.
struct GameStarSource: Sendable {
    /// The kind of the game's queued star write.
    var operationKind: SyncPendingOperationKind
    /// The idempotency scope of a star write for the round or figure.
    var scope: @Sendable (_ id: UUID) -> String
    /// The request data of a star write: the id, the value, and when it was made.
    var payload: @Sendable (_ id: UUID, _ starred: Bool, _ createdAt: Date) throws -> Data
    /// The id and value of a queued star write. Nil for data it can't read.
    var queued: @Sendable (_ requestData: Data) -> (id: UUID, starred: Bool)?
    /// The ids this person starred, as the game's cache last heard from the server.
    var serverStars: @Sendable (_ ownerUserID: UUID) async -> Set<UUID>
    /// Keeps the server's answer for these ids in the game's cache.
    var saveServerStars: @Sendable (_ stars: [UUID: Bool], _ ownerUserID: UUID) async -> Void
}
