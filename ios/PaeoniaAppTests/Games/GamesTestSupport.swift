import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// Shorthand for the deterministic Games fixtures the developer scenarios use.
typealias GameFixture = DeveloperGamesFixture

/// Records every Games call and fails the ones a test lists. A class with a lock,
/// so tests read its record without `await`.
final class ScriptedGamesGateway: GamesGateway, @unchecked Sendable {
    struct Failure: Error {}

    /// What a guess sent along about the speed bonus.
    struct GuessClaim: Equatable {
        var speedBonus: Bool?
        var solveMs: Int?
    }

    private struct Record {
        var calls: [String] = []
        var presence: [Bool] = []
        var pickedWords: [GamePickWordPayload] = []
        var submittedDrawings: [(roundID: UUID, assetID: UUID)] = []
        var guesses: [String] = []
        var guessClaims: [GuessClaim] = []
        var seenRounds: [UUID] = []
        var savePromptAnswers: [UUID] = []
        var inviteCount = 0
        var failing: Set<String> = []
        var pickError: PaeoniaConvexError?
        var submitError: PaeoniaConvexError?
        var guessError: PaeoniaConvexError?
        var guessErrorOnlyWithClaim = false
        var giveUpError: PaeoniaConvexError?
        var inviteError: (any Error)?
        var stateToLoad: RemoteDrawAndGuessState?
        var roundsToLoad: [UUID: RemoteDrawAndGuessRound] = [:]
    }

    private let lock = NSLock()
    private var record = Record()

    private func read<T>(_ value: (Record) -> T) -> T {
        lock.withLock { value(record) }
    }

    private func write(_ change: (inout Record) -> Void) {
        lock.withLock { change(&record) }
    }

    var calls: [String] { read(\.calls) }
    var presence: [Bool] { read(\.presence) }
    var pickedWords: [GamePickWordPayload] { read(\.pickedWords) }
    var submittedDrawings: [(roundID: UUID, assetID: UUID)] { read(\.submittedDrawings) }
    var guesses: [String] { read(\.guesses) }
    var guessClaims: [GuessClaim] { read(\.guessClaims) }
    var seenRounds: [UUID] { read(\.seenRounds) }
    var savePromptAnswers: [UUID] { read(\.savePromptAnswers) }
    var inviteCount: Int { read(\.inviteCount) }

    func fail(_ name: String) {
        write { $0.failing.insert(name) }
    }

    func unfail(_ name: String) {
        write { $0.failing.remove(name) }
    }

    func setPickError(_ error: PaeoniaConvexError?) {
        write { $0.pickError = error }
    }

    func setSubmitError(_ error: PaeoniaConvexError?) {
        write { $0.submitError = error }
    }

    /// Refuses guesses. With `whenClaiming`, only the ones that carry a speed
    /// bonus claim are refused, like a server that does not know those fields.
    func setGuessError(_ error: PaeoniaConvexError?, whenClaiming: Bool = false) {
        write {
            $0.guessError = error
            $0.guessErrorOnlyWithClaim = whenClaiming
        }
    }

    func setGiveUpError(_ error: PaeoniaConvexError?) {
        write { $0.giveUpError = error }
    }

    func setInviteError(_ error: (any Error)?) {
        write { $0.inviteError = error }
    }

    func setStateToLoad(_ state: RemoteDrawAndGuessState?) {
        write { $0.stateToLoad = state }
    }

    /// What `loadDrawAndGuessRound` finds. A round not set here does not exist.
    func setRoundToLoad(_ round: RemoteDrawAndGuessRound) {
        write { $0.roundsToLoad[round.id] = round }
    }

    private func begin(_ name: String) throws {
        let shouldFail = lock.withLock {
            record.calls.append(name)
            return record.failing.contains(name)
        }
        if shouldFail {
            throw Failure()
        }
    }

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings {
        try begin("setSettings")
        return RemoteGameSettings(
            coupleID: DeveloperScenarioFixture.coupleID,
            playStyle: playStyle,
            language: language,
            updatedByUserID: GameFixture.me,
            createdAt: GameFixture.now,
            updatedAt: GameFixture.now
        )
    }

    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
        try begin("ensure")
        return RemoteEnsureGameResult(gameID: GameFixture.gameID, created: true)
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
        try begin("load")
        guard let state = read(\.stateToLoad) else { throw Failure() }
        return state
    }

    func loadDrawAndGuessRound(roundID: UUID) async throws -> RemoteDrawAndGuessRound? {
        try begin("loadRound")
        return read { $0.roundsToLoad[roundID] }
    }

    func pickWord(_ pick: GamePickWordPayload, operation _: SyncClientOperation) async throws -> RemotePickedWord {
        try begin("pick")
        if let error = read(\.pickError) { throw error }
        write { $0.pickedWords.append(pick) }
        return RemotePickedWord(
            roundID: pick.roundID,
            roundNumber: 1,
            difficulty: pick.choice,
            word: pick.word,
            points: pick.points
        )
    }

    func submitDrawing(
        roundID: UUID,
        mediaAssetID: UUID,
        operation _: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult {
        try begin("submitDrawing")
        if let error = read(\.submitError) { throw error }
        write { $0.submittedDrawings.append((roundID, mediaAssetID)) }
        return RemoteSubmitDrawingResult(roundID: roundID, roundState: .guessing, drawingSubmittedAt: GameFixture.now)
    }

    func markRoundSeen(roundID: UUID) async throws -> RemoteMarkSeenResult {
        try begin("markSeen")
        write { $0.seenRounds.append(roundID) }
        return RemoteMarkSeenResult(guesserFirstSeenAt: GameFixture.now)
    }

    func submitGuess(
        roundID _: UUID,
        guess: String,
        speedBonus: Bool?,
        solveMs: Int?,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        try begin("guess")
        if let error = read(\.guessError), !read(\.guessErrorOnlyWithClaim) || speedBonus != nil || solveMs != nil {
            throw error
        }
        write {
            $0.guesses.append(guess)
            $0.guessClaims.append(GuessClaim(speedBonus: speedBonus, solveMs: solveMs))
        }
        return RemoteGuessResult(
            guessID: UUID(),
            correct: false,
            roundState: .guessing,
            points: 0,
            speedBonus: 0,
            solveMs: nil,
            createdAt: GameFixture.now
        )
    }

    func giveUp(roundID: UUID, operation _: SyncClientOperation) async throws -> RemoteGiveUpResult {
        try begin("giveUp")
        if let error = read(\.giveUpError) { throw error }
        return RemoteGiveUpResult(roundID: roundID, roundState: .missed)
    }

    func respondSavePrompt(roundID: UUID) async throws {
        try begin("respondSavePrompt")
        write { $0.savePromptAnswers.append(roundID) }
    }

    func saveRoundToMemories(
        roundID _: UUID,
        memoryID: UUID,
        mediaAssetID _: UUID,
        memoryDate _: String
    ) async throws -> RemoteSaveRoundResult {
        try begin("saveRound")
        return RemoteSaveRoundResult(memoryID: memoryID, created: true)
    }

    func sendInvite() async throws -> RemoteInviteResult {
        try begin("invite")
        if let error = read(\.inviteError) { throw error }
        write { $0.inviteCount += 1 }
        return RemoteInviteResult(sentAt: GameFixture.now)
    }

    func setPresence(_ isPresent: Bool) async throws {
        write {
            $0.calls.append("presence")
            $0.presence.append(isPresent)
        }
    }
}

/// Uploads succeed with a fixed asset, and downloads return the fixture umbrella.
final class ScriptedDrawingTransfer: GameDrawingTransferring, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedUploads: [(roundID: UUID, bytes: Int)] = []
    private var recordedDownloads: [UUID] = []

    var uploads: [(roundID: UUID, bytes: Int)] { lock.withLock { recordedUploads } }
    var downloads: [UUID] { lock.withLock { recordedDownloads } }

    func uploadDrawing(
        _ data: Data,
        gameID _: UUID,
        roundID: UUID,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        lock.withLock { recordedUploads.append((roundID, data.count)) }
        return GameFixture.assetID
    }

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data {
        lock.withLock { recordedDownloads.append(mediaAssetID) }
        return await MainActor.run { GameFixture.umbrella().dataRepresentation() }
    }
}

/// Everything a Games test needs, in memory.
@MainActor
struct GamesTestEnvironment {
    let gateway = ScriptedGamesGateway()
    let transfer = ScriptedDrawingTransfer()
    let cache: InMemoryGamesCache
    let pending = InMemoryPendingSyncOperationRepository()
    let drawingStore = InMemoryGameDrawingStore()
    let operations = DeveloperScenarioOperationProvider()

    init(state: RemoteDrawAndGuessState?, hasSeenSettings: Bool = true) {
        cache = InMemoryGamesCache(
            state: state,
            ownerUserID: GameFixture.me,
            hasSeenSettings: hasSeenSettings
        )
    }

    func dependencies(live: WidgetLiveDrawing? = nil) -> GamesDependencies {
        GamesDependencies(
            gateway: gateway,
            cache: cache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: drawingStore,
            drawingTransfer: transfer,
            makeLive: { _ in live },
            now: { GameFixture.now }
        )
    }

    func viewModel(
        live: WidgetLiveDrawing? = nil,
        heartbeat: Duration = .seconds(3_600),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> DrawAndGuessViewModel {
        DrawAndGuessViewModel(
            dependencies: dependencies(live: live),
            participants: GameFixture.participants,
            heartbeatInterval: heartbeat,
            tickInterval: .seconds(3_600),
            sleep: sleep
        )
    }

    /// The operations still waiting, by kind.
    func queued(_ kind: SyncPendingOperationKind) async -> [PendingSyncOperationSnapshot] {
        (try? await pending.inFlightOperations(ownerUserID: GameFixture.me, kind: kind)) ?? []
    }
}

/// A live room with no relay, plus the connection to feed it messages.
@MainActor
func makeOfflineLiveRoom() -> (room: WidgetLiveDrawing, connection: WidgetLiveConnection) {
    let connection = WidgetLiveConnection(coupleID: DeveloperScenarioFixture.coupleID, ticketProvider: { _ in nil })
    return (WidgetLiveDrawing(connection: connection, role: .watching), connection)
}

/// Waits until `condition` holds, for work the view model starts in a task.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

func snapshot(
    _ kind: SyncPendingOperationKind,
    _ payload: some Encodable,
    owner: UUID = GameFixture.me,
    operation: SyncClientOperation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
) throws -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: owner,
        operation: operation,
        operationKind: kind,
        idempotencyScope: "games",
        requestHash: nil,
        requestData: try JSONEncoder().encode(payload),
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}

func syncContext(_ store: any PendingSyncOperationPersisting) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: GameFixture.me),
        reason: .localChange,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: store
    )
}
