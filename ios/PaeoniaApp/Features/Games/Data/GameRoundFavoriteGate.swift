import Foundation

/// A Draw & Guess round can be starred once it is finished, so a star waits for this
/// person's queued guesses and give ups of the round. The server would otherwise refuse
/// it as "not finished".
struct GameRoundFavoriteGate: FavoriteSendGating {
    func mustWait(
        for target: FavoriteTarget,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        try await hasEarlierGameMove(in: target.id, before: operation, context: context)
    }
}
