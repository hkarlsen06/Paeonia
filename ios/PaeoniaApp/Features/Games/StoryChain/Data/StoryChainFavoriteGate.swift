import Foundation

/// A story can be starred once it is finished, so a star waits for this person's queued
/// title of the story. The server would otherwise refuse it as "not finished".
struct StoryChainFavoriteGate: FavoriteSendGating {
    func mustWait(
        for target: FavoriteTarget,
        operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> Bool {
        try await hasQueuedStoryChainWrite(
            of: [.storyChainNameStory],
            storyID: target.id,
            besides: operation,
            context: context
        )
    }
}
