import Foundation

/// The pending operation handlers of every built game. `PaeoniaSyncServiceDefaults`
/// adds them to the outbox drain.
nonisolated enum GamesPendingOperationRegistry {
    /// Each built game adds its handlers through a function below, built from the
    /// shared `gateway` (which conforms to the game's own gateway protocol) and
    /// `cache`. Its `SyncPendingOperationKind` cases carry the game's Swift prefix.
    static func handlers(client: PaeoniaConvexClient) -> [any PendingSyncOperationHandling] {
        let gateway = LiveGamesGateway(client: client)
        let cache = FileGamesCache.shared
        return drawAndGuessHandlers(client: client, gateway: gateway, cache: cache)
            + storyChainHandlers(gateway: gateway, cache: cache)
            + mindMeldHandlers(gateway: gateway)
            + consensioHandlers(gateway: gateway)
            + guessMySpotHandlers(gateway: gateway)
            + exquisiteCorpseHandlers(client: client)
            + boardGameHandlers(client: client)
    }

    /// What each game's items wait for before they can be favorited (see `FavoriteSendGating`).
    static func favoriteGates() -> [FavoriteKind: any FavoriteSendGating] {
        [
            .gameRound: GameRoundFavoriteGate(),
            .storyChainStory: StoryChainFavoriteGate(),
            .corpseFigure: ExquisiteCorpseFavoriteGate(),
        ]
    }

    private static func drawAndGuessHandlers(
        client: PaeoniaConvexClient,
        gateway: LiveGamesGateway,
        cache: FileGamesCache
    ) -> [any PendingSyncOperationHandling] {
        [
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
            GameResultSeenPendingOperationHandler(gateway: gateway, cache: cache),
        ]
    }

    private static func storyChainHandlers(
        gateway: LiveGamesGateway,
        cache: FileGamesCache
    ) -> [any PendingSyncOperationHandling] {
        [
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
        ]
    }

    private static func consensioHandlers(gateway: LiveGamesGateway) -> [any PendingSyncOperationHandling] {
        [
            ConsensioPlacePendingOperationHandler(gateway: gateway, cache: FileConsensioCache.shared),
            ConsensioGuessPendingOperationHandler(gateway: gateway, cache: FileConsensioCache.shared),
            ConsensioRevealSeenOperationHandler(gateway: gateway, cache: FileConsensioCache.shared),
        ]
    }

    private static func guessMySpotHandlers(gateway: LiveGamesGateway) -> [any PendingSyncOperationHandling] {
        let cache = FileGuessMySpotCache.shared
        return [
            GuessMySpotSendPendingOperationHandler(
                gateway: gateway,
                cache: cache,
                photos: FileGuessMySpotPhotoStore.shared,
                namer: LiveGuessMySpotPlaceNamer(),
                imageCache: MemoryMediaImageDiskCache()
            ),
            GuessMySpotGuessPendingOperationHandler(gateway: gateway, cache: cache),
            GuessMySpotRevealSeenOperationHandler(gateway: gateway, cache: cache),
            GuessMySpotDeleteRoundOperationHandler(gateway: gateway, cache: cache),
        ]
    }

    private static func mindMeldHandlers(gateway: LiveGamesGateway) -> [any PendingSyncOperationHandling] {
        [
            LockMindMeldWordPendingOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            CountMindMeldPendingOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            MindMeldRevealSeenOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
            MindMeldEndSeenOperationHandler(gateway: gateway, cache: FileMindMeldCache.shared),
        ]
    }

    private static func exquisiteCorpseHandlers(
        client: PaeoniaConvexClient
    ) -> [any PendingSyncOperationHandling] {
        let corpseGateway = LiveExquisiteCorpseGateway(client: client)
        let corpseCache = FileExquisiteCorpseCache.shared
        return [
            ExquisiteCorpseSubmitPartHandler(
                gateway: corpseGateway,
                transfer: LiveGameDrawingTransfer(client: client),
                cache: corpseCache,
                drawingStore: FileGameDrawingStore.shared
            ),
            ExquisiteCorpseRevealSeenHandler(gateway: corpseGateway, cache: corpseCache),
        ]
    }

    private static func boardGameHandlers(client: PaeoniaConvexClient) -> [any PendingSyncOperationHandling] {
        let boardGamesGateway = LiveBoardGamesGateway(client: client)
        return [
            BoardGameMovePendingOperationHandler(gateway: boardGamesGateway, cache: FileBoardGamesCache.shared),
            BoardGameRematchPendingOperationHandler(gateway: boardGamesGateway, cache: FileBoardGamesCache.shared),
        ]
    }
}
