import Foundation

/// The single list of live feeds. A feature adds one line to `makeFeeds`.
///
/// ```swift
/// static func makeFeeds(stores: PaeoniaSyncServiceDefaults.Stores) -> [any LiveFeed] {
///     [
///         LocationLiveFeed(visibilityStore: stores.locationVisibilityStore),
///     ]
/// }
/// ```
nonisolated enum LiveFeedRegistry {
    static func makeFeeds(stores: PaeoniaSyncServiceDefaults.Stores) -> [any LiveFeed] {
        [
            AccessLiveFeed(snapshotStore: stores.accessSnapshotStore),
            RelationshipEventsLiveFeed.make(stores: stores),
            LocationVisibilityLiveFeed(
                visibilityStore: stores.locationVisibilityStore,
                pendingOperationStore: stores.pendingOperationStore
            ),
            WidgetCanvasLiveFeed(syncer: WidgetCanvasSyncServiceFactory.makeDefault()),
            MemoryLiveFeed(memoryStore: stores.memoryStore, stateStore: stores.stateStore),
            DailyChallengeLiveFeed(cache: FileDailyChallengeSnapshotCache.live()),
            DailyQuestionChatLiveFeed(cache: FileDailyQuestionChatCache.shared),
            GamesOverviewLiveFeed(cache: FileGamesCache.shared),
            DrawAndGuessLiveFeed(cache: FileGamesCache.shared),
            StoryChainLiveFeed(cache: FileStoryChainCache.shared),
            MindMeldLiveFeed(cache: FileMindMeldCache.shared),
            ExquisiteCorpseLiveFeed(cache: FileExquisiteCorpseCache.shared),
            BoardGamesLiveFeed(cache: FileBoardGamesCache.shared),
            BoardGameMarksLiveFeed(cache: FileBoardGamesCache.shared),
            HeartsLiveFeed(cache: FileHeartsCache.shared),
            CoupleDatesLiveFeed(cache: FileCoupleDatesCache.shared),
            StoriesLiveFeed(cache: FileStoriesCache.shared),
        ]
    }
}
