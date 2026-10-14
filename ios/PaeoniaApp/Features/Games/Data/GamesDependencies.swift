import Foundation

/// Everything the Games screens use outside the view models. Production builds
/// it from the shared Convex client and the on-disk stores. Tests and the
/// developer scenarios build it from in-memory parts.
@MainActor
struct GamesDependencies {
    var gateway: any DrawAndGuessGateway
    var cache: any GamesCaching
    var pendingOperationStore: any PendingSyncOperationPersisting
    var operationProvider: any SyncClientOperationProviding
    var drawingStore: any GameDrawingStoring
    var drawingTransfer: any GameDrawingTransferring
    /// Builds the live drawing room for the couple, or nil when there is none.
    var makeLive: @MainActor (UUID) -> WidgetLiveDrawing?
    var now: @Sendable () -> Date = { Date() }
    // Each built game adds its own dependency fields here, after `now`. Give each
    // a default that works offline, so a test that builds `GamesDependencies`
    // memberwise does not change when a game adds a field.
    var storyChainGateway: any StoryChainGateway = UnavailableGamesGateway()
    var storyChainCache: any StoryChainCaching = InMemoryStoryChainCache()
    /// Builds the Story Chain relay room for the couple, or nil when there is none.
    var makeStoryChainLive: @MainActor (UUID) -> WidgetLiveDrawing? = { _ in nil }

    // Mind Meld
    var mindMeldGateway: any MindMeldGateway = UnavailableGamesGateway()
    var mindMeldCache: any MindMeldCaching = InMemoryMindMeldCache()
    /// The Mind Meld relay room for the couple: presence and typing only.
    var makeMindMeldLive: @MainActor (UUID) -> WidgetLiveDrawing? = { _ in nil }

    // Exquisite corpse
    var exquisiteCorpseGateway: any ExquisiteCorpseGateway = UnavailableExquisiteCorpseGateway()
    var exquisiteCorpseCache: any ExquisiteCorpseCaching = InMemoryExquisiteCorpseCache()
    /// Builds Exquisite corpse's live room for the couple, or nil when there is none.
    var makeExquisiteCorpseLive: @MainActor (UUID) -> WidgetLiveDrawing? = { _ in nil }
    // Board games
    var boardGamesGateway: any BoardGamesGateway = UnavailableBoardGamesGateway()
    var boardGamesCache: any BoardGamesCaching = InMemoryBoardGamesCache()
    /// Loads the hidden photo under Dots and Boxes, the way Memories loads photos.
    var memoryPhotos: (any MemoryMediaImageProviding)?

    static func live() -> GamesDependencies {
        let client = try? PaeoniaConvexClientProvider.shared.client()
        let pendingStore: any PendingSyncOperationPersisting
        if let localStore = PaeoniaLocalStore.shared {
            pendingStore = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        } else {
            pendingStore = InMemoryPendingSyncOperationRepository()
        }
        return GamesDependencies(
            gateway: client.map { LiveGamesGateway(client: $0) } ?? UnavailableGamesGateway(),
            cache: FileGamesCache.shared,
            pendingOperationStore: pendingStore,
            operationProvider: SyncClientOperationFactory.shared,
            drawingStore: FileGameDrawingStore.shared,
            drawingTransfer: client.map { LiveGameDrawingTransfer(client: $0) } ?? UnavailableGameDrawingTransfer(),
            makeLive: { DrawAndGuessLive.make(coupleID: $0) },
            storyChainGateway: client.map { LiveGamesGateway(client: $0) } ?? UnavailableGamesGateway(),
            storyChainCache: FileStoryChainCache.shared,
            makeStoryChainLive: { StoryChainLive.make(coupleID: $0) },
            mindMeldGateway: client.map { LiveGamesGateway(client: $0) } ?? UnavailableGamesGateway(),
            mindMeldCache: FileMindMeldCache.shared,
            makeMindMeldLive: { MindMeldLive.make(coupleID: $0) },
            exquisiteCorpseGateway: client.map { LiveExquisiteCorpseGateway(client: $0) }
                ?? UnavailableExquisiteCorpseGateway(),
            exquisiteCorpseCache: FileExquisiteCorpseCache.shared,
            makeExquisiteCorpseLive: { ExquisiteCorpseLive.make(coupleID: $0) },
            boardGamesGateway: client.map { LiveBoardGamesGateway(client: $0) } ?? UnavailableBoardGamesGateway(),
            boardGamesCache: FileBoardGamesCache.shared,
            memoryPhotos: MemoryMediaImageProviderFactory.shared
        )
    }
}

// The protocols are async, and these stand-ins fail at once.
// swiftlint:disable async_without_await

/// Used when the build has no Convex URL, so every call fails and the screens
/// show what is cached.
nonisolated struct UnavailableGamesGateway: GamesGateway {
    struct Unavailable: Error {}

    func setSettings(playStyle _: GamePlayStyle, language _: GameLanguage) async throws -> RemoteGameSettings {
        throw Unavailable()
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        throw Unavailable()
    }

    func setPresence(_: GameKind, isPresent _: Bool) async throws {
        throw Unavailable()
    }

    func sendInvite(_: GameKind) async throws -> RemoteInviteResult {
        throw Unavailable()
    }
}

// Each built game adds its own `extension UnavailableGamesGateway` here.
nonisolated extension UnavailableGamesGateway: DrawAndGuessGateway {
    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
        throw Unavailable()
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
        throw Unavailable()
    }

    func loadDrawAndGuessRound(roundID _: UUID) async throws -> RemoteDrawAndGuessRound? {
        throw Unavailable()
    }

    func pickWord(_: GamePickWordPayload, operation _: SyncClientOperation) async throws -> RemotePickedWord {
        throw Unavailable()
    }

    func submitDrawing(
        roundID _: UUID,
        mediaAssetID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult {
        throw Unavailable()
    }

    func markRoundSeen(roundID _: UUID) async throws -> RemoteMarkSeenResult {
        throw Unavailable()
    }

    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID _: UUID,
        guess _: String,
        speedBonus _: Int?,
        solveMs _: Int?,
        hintsUsed _: Int?,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        throw Unavailable()
    }

    func giveUp(roundID _: UUID, operation _: SyncClientOperation) async throws -> RemoteGiveUpResult {
        throw Unavailable()
    }

    func setRoundReaction(roundID _: UUID, reaction _: DrawAndGuessReaction?) async throws -> RemoteReactionResult {
        throw Unavailable()
    }

    func markRoundResultSeen(roundID _: UUID) async throws -> RemoteResultSeenResult {
        throw Unavailable()
    }

    func loadDrawAndGuessHistory(
        starredOnly _: Bool,
        beforeRoundNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteDrawAndGuessHistoryPage {
        throw Unavailable()
    }

    func loadDrawAndGuessRecords() async throws -> RemoteDrawAndGuessRecords {
        throw Unavailable()
    }

    func setRoundStar(roundID _: UUID, starred _: Bool) async throws -> RemoteRoundStarResult {
        throw Unavailable()
    }
}

nonisolated struct UnavailableGameDrawingTransfer: GameDrawingTransferring {
    func uploadDrawing(
        _: Data,
        parent _: GameUploadParent,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        throw UnavailableGamesGateway.Unavailable()
    }

    func downloadDrawing(mediaAssetID _: UUID) async throws -> Data {
        throw UnavailableGamesGateway.Unavailable()
    }
}
// swiftlint:enable async_without_await
