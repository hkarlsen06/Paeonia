import Foundation
@testable import PaeoniaApp

/// The Exquisite corpse gateway for one person, through their phone's network,
/// so faults, offline and force quits apply to every call. It also answers the
/// shared Games calls (overview, presence, invites) that the game's screen makes
/// through `GamesDependencies.gateway`.
final class CorpseSimGateway: DrawAndGuessGateway, ExquisiteCorpseGateway, @unchecked Sendable {
    private let user: UUID
    private let server: CorpseSimServer
    private let network: SimNetwork
    private let incarnation: Int

    @MainActor
    init(user: UUID, server: CorpseSimServer, network: SimNetwork) {
        self.user = user
        self.server = server
        self.network = network
        incarnation = network.incarnation
    }

    @MainActor
    private func call<T>(_ name: String, _ apply: @MainActor (CorpseSimServer, UUID) throws -> T) async throws -> T {
        try await network.call(name, from: incarnation) { try apply(server, user) }
    }

    // MARK: Exquisite corpse

    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult {
        try await call("ensure") { $0.ensureGame(user: $1) }
    }

    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState {
        try await call("load") { $0.state(for: $1) }
    }

    func submitExquisiteCorpsePart(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        drawingAssetID: UUID,
        stripAssetID: UUID?,
        operation: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult {
        try await call("submitPart") {
            try $0.submitPart(
                user: $1,
                payload: payload,
                drawingAssetID: drawingAssetID,
                stripAssetID: stripAssetID,
                operation: operation
            )
        }
    }

    func markExquisiteCorpseRevealSeen(figureID: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult {
        try await call("revealSeen") { try $0.markRevealSeen(user: $1, figureID: figureID) }
    }

    // swiftlint:disable async_without_await
    func loadExquisiteCorpseHistory(
        starredOnly _: Bool,
        beforeFigureNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage {
        throw URLError(.notConnectedToInternet)
    }

    func loadExquisiteCorpseFigure(figureID _: UUID) async throws -> RemoteExquisiteCorpseFigure? {
        throw URLError(.notConnectedToInternet)
    }

    // swiftlint:enable async_without_await

    // MARK: Shared Games calls

    func setSettings(playStyle _: GamePlayStyle, language _: GameLanguage) async throws -> RemoteGameSettings {
        try await call("setSettings") { server, _ in server.settings }
    }

    func markSettingsSeen() async throws -> RemoteGameSettings {
        try await call("markSettingsSeen") { server, _ in server.settings }
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        try await call("overview") { $0.overview(for: $1) }
    }

    func sendInvite(_: GameKind) async throws -> RemoteInviteResult {
        try await call("invite") { try $0.sendInvite(user: $1) }
    }

    func setPresence(_: GameKind, isPresent: Bool) async throws {
        try await call("presence") { $0.setPresence(user: $1, present: isPresent) }
    }

    /// The relay ticket. It changes nothing on the server.
    func fetchLiveTicket() async throws {
        try await call("ticket") { _, _ in () }
    }

    // MARK: Draw & Guess, which this game never calls

    // swiftlint:disable async_without_await

    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult { throw Unused() }
    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState { throw Unused() }
    func loadDrawAndGuessRound(roundID _: UUID) async throws -> RemoteDrawAndGuessRound? { throw Unused() }
    func pickWord(_: GamePickWordPayload, operation _: SyncClientOperation) async throws -> RemotePickedWord {
        throw Unused()
    }

    func submitDrawing(
        roundID _: UUID,
        mediaAssetID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult {
        throw Unused()
    }

    func markRoundSeen(roundID _: UUID) async throws -> RemoteMarkSeenResult { throw Unused() }

    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID _: UUID,
        guess _: String,
        speedBonus _: Int?,
        solveMs _: Int?,
        hintsUsed _: Int?,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        throw Unused()
    }

    func giveUp(roundID _: UUID, operation _: SyncClientOperation) async throws -> RemoteGiveUpResult {
        throw Unused()
    }

    func markRoundResultSeen(roundID _: UUID) async throws -> RemoteResultSeenResult { throw Unused() }

    func loadDrawAndGuessHistory(
        starredOnly _: Bool,
        beforeRoundNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteDrawAndGuessHistoryPage {
        throw Unused()
    }

    func loadDrawAndGuessHistoryRound(roundID _: UUID) async throws -> RemoteDrawAndGuessHistoryRound? {
        throw Unused()
    }

    func loadDrawAndGuessRecords() async throws -> RemoteDrawAndGuessRecords { throw Unused() }

    // swiftlint:enable async_without_await

    struct Unused: Error {}
}

/// Drawing uploads and downloads through the phone's network.
final class CorpseSimTransfer: GameDrawingTransferring, @unchecked Sendable {
    private let user: UUID
    private let server: CorpseSimServer
    private let network: SimNetwork
    private let incarnation: Int

    @MainActor
    init(user: UUID, server: CorpseSimServer, network: SimNetwork) {
        self.user = user
        self.server = server
        self.network = network
        incarnation = network.incarnation
    }

    func uploadDrawing(
        _ data: Data,
        parent: GameUploadParent,
        coupleID _: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        try await upload(data, parent: parent, reserveOperation: reserveOperation)
    }

    @MainActor
    private func upload(
        _ data: Data,
        parent: GameUploadParent,
        reserveOperation: SyncClientOperation
    ) async throws -> UUID {
        try await network.call("upload", from: incarnation) {
            try server.upload(user: user, data: data, parent: parent, reserveOperation: reserveOperation)
        }
    }

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data {
        try await download(mediaAssetID)
    }

    @MainActor
    private func download(_ assetID: UUID) async throws -> Data {
        try await network.call("download", from: incarnation) { try server.download(user: user, assetID: assetID) }
    }
}
