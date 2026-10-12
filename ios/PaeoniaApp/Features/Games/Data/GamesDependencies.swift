import Foundation

/// Everything the Games screens use outside the view models. Production builds
/// it from the shared Convex client and the on-disk stores. Tests and the
/// developer scenarios build it from in-memory parts.
@MainActor
struct GamesDependencies {
    var gateway: any GamesGateway
    var cache: any GamesCaching
    var pendingOperationStore: any PendingSyncOperationPersisting
    var operationProvider: any SyncClientOperationProviding
    var drawingStore: any GameDrawingStoring
    var drawingTransfer: any GameDrawingTransferring
    /// Builds the live drawing room for the couple, or nil when there is none.
    var makeLive: @MainActor (UUID) -> WidgetLiveDrawing?
    var now: @Sendable () -> Date = { Date() }

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
            makeLive: { DrawAndGuessLive.make(coupleID: $0) }
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

    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
        throw Unavailable()
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
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

    func submitGuess(
        roundID _: UUID,
        guess _: String,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        throw Unavailable()
    }

    func giveUp(roundID _: UUID, operation _: SyncClientOperation) async throws -> RemoteGiveUpResult {
        throw Unavailable()
    }

    func respondSavePrompt(roundID _: UUID) async throws {
        throw Unavailable()
    }

    func saveRoundToMemories(
        roundID _: UUID,
        memoryID _: UUID,
        mediaAssetID _: UUID,
        memoryDate _: String
    ) async throws -> RemoteSaveRoundResult {
        throw Unavailable()
    }

    func sendInvite() async throws -> RemoteInviteResult {
        throw Unavailable()
    }

    func setPresence(_: Bool) async throws {
        throw Unavailable()
    }
}

nonisolated struct UnavailableGameDrawingTransfer: GameDrawingTransferring {
    func uploadDrawing( // swiftlint:disable:this function_parameter_count
        _: Data,
        gameID _: UUID,
        roundID _: UUID,
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
