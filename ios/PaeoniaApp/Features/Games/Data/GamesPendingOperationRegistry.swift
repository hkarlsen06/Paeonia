import Foundation

/// The pending operation handlers of every built game. `PaeoniaSyncServiceDefaults`
/// adds them to the outbox drain.
nonisolated enum GamesPendingOperationRegistry {
    static func handlers(client: PaeoniaConvexClient) -> [any PendingSyncOperationHandling] {
        let gateway = LiveGamesGateway(client: client)
        let cache = FileGamesCache.shared
        let corpseGateway = LiveExquisiteCorpseGateway(client: client)
        let corpseCache = FileExquisiteCorpseCache.shared
        let boardGamesGateway = LiveBoardGamesGateway(client: client)

        // Each built game appends its handlers below, built from `gateway` (which
        // conforms to the game's own gateway protocol) and `cache`. Its
        // `SyncPendingOperationKind` cases carry the game's Swift prefix.
        return [
            // Draw & Guess
            PickDrawWordPendingOperationHandler(
                gateway: gateway,
                cache: cache,
                drawingStore: FileGameDrawingStore.shared
            ),
            SubmitGameDrawingPendingOperationHandler(
                gateway: gateway,
                transfer: LiveGameDrawingTransfer(client: client),
                cache: cache,
                drawingStore: FileGameDrawingStore.shared
            ),
            SubmitGameGuessPendingOperationHandler(gateway: gateway, cache: cache),
            GiveUpGameRoundPendingOperationHandler(gateway: gateway, cache: cache),
            SetGameRoundStarPendingOperationHandler(gateway: gateway, cache: cache),
            GameReactionPendingOperationHandler(gateway: gateway, cache: cache),
            GameResultSeenPendingOperationHandler(gateway: gateway, cache: cache),
            // Story Chain
            StoryChainStartPendingOperationHandler(
                gateway: gateway, cache: FileStoryChainCache.shared, gamesCache: cache
            ),
            StoryChainLinePendingOperationHandler(
                gateway: gateway, cache: FileStoryChainCache.shared, gamesCache: cache
            ),
            StoryChainNamePendingOperationHandler(
                gateway: gateway, cache: FileStoryChainCache.shared, gamesCache: cache
            ),
            StoryChainSeenPendingOperationHandler(gateway: gateway, cache: FileStoryChainCache.shared),
            StoryChainStarPendingOperationHandler(
                gateway: gateway, cache: FileStoryChainCache.shared, gamesCache: cache
            ),
            // Mind Meld
            LockMindMeldWordPendingOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            CountMindMeldPendingOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            MindMeldRevealSeenOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            MindMeldEndSeenOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            // Exquisite corpse
            ExquisiteCorpseSubmitPartHandler(
                gateway: corpseGateway,
                transfer: LiveGameDrawingTransfer(client: client),
                cache: corpseCache,
                drawingStore: FileGameDrawingStore.shared
            ),
            ExquisiteCorpseRevealSeenHandler(gateway: corpseGateway, cache: corpseCache),
            ExquisiteCorpseStarHandler(gateway: corpseGateway, cache: corpseCache),
            // Board games
            BoardGameMovePendingOperationHandler(gateway: boardGamesGateway, cache: FileBoardGamesCache.shared),
            BoardGameRematchPendingOperationHandler(gateway: boardGamesGateway, cache: FileBoardGamesCache.shared),
        ]
    }
}
