import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

/// Shorthand for the deterministic Games fixtures the developer scenarios use.
typealias GameFixture = DeveloperGamesFixture

/// Records every Games call and fails the ones a test lists. A class with a lock,
/// so tests read its record without `await`.
final class ScriptedGamesGateway: DrawAndGuessGateway, @unchecked Sendable {
    struct Failure: Error {}

    /// What a guess sent along about the speed bonus and the hints.
    struct GuessClaim: Equatable {
        var speedBonus: Int?
        var solveMs: Int?
        var hintsUsed: Int?
    }

    /// A reaction the phone sent. The reaction is nil when it cleared one.
    struct SentReaction: Equatable {
        var roundID: UUID
        var reaction: DrawAndGuessReaction?
    }

    private struct Record {
        var calls: [String] = []
        var presence: [Bool] = []
        var presenceKinds: [GameKind] = []
        var pickedWords: [GamePickWordPayload] = []
        var submittedDrawings: [(roundID: UUID, assetID: UUID)] = []
        var guesses: [String] = []
        var guessClaims: [GuessClaim] = []
        var seenRounds: [UUID] = []
        var reactions: [SentReaction] = []
        var resultSeenRounds: [UUID] = []
        var inviteCount = 0
        var inviteKinds: [GameKind] = []
        var failing: Set<String> = []
        var pickError: PaeoniaConvexError?
        var submitError: PaeoniaConvexError?
        var guessError: PaeoniaConvexError?
        var guessErrorOnlyWithClaim = false
        var giveUpError: PaeoniaConvexError?
        var reactionError: PaeoniaConvexError?
        var inviteError: (any Error)?
        var stateToLoad: RemoteDrawAndGuessState?
        var settingsSeen = false
        var roundsToLoad: [UUID: RemoteDrawAndGuessRound] = [:]
        var historyRounds: [RemoteDrawAndGuessHistoryRound] = []
        var historyRequests: [HistoryRequest] = []
        var recordsToLoad: RemoteDrawAndGuessRecords?
        var starWrites: [StarWrite] = []
        var starError: PaeoniaConvexError?
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
    /// The game each `presence` call named.
    var presenceKinds: [GameKind] { read(\.presenceKinds) }
    var pickedWords: [GamePickWordPayload] { read(\.pickedWords) }
    var submittedDrawings: [(roundID: UUID, assetID: UUID)] { read(\.submittedDrawings) }
    var guesses: [String] { read(\.guesses) }
    var guessClaims: [GuessClaim] { read(\.guessClaims) }
    var seenRounds: [UUID] { read(\.seenRounds) }
    var reactions: [SentReaction] { read(\.reactions) }
    var resultSeenRounds: [UUID] { read(\.resultSeenRounds) }
    var inviteCount: Int { read(\.inviteCount) }
    /// The game each invite named.
    var inviteKinds: [GameKind] { read(\.inviteKinds) }

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

    func setReactionError(_ error: PaeoniaConvexError?) {
        write { $0.reactionError = error }
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

    /// Like the server, this person counts as having seen the settings from now on.
    func markSettingsSeen() throws -> RemoteGameSettings {
        try begin("markSettingsSeen")
        write { $0.settingsSeen = true }
        guard let settings = try overviewToLoad().settings else { throw Failure() }
        return settings
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

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) throws -> RemoteGameSettings {
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

    func ensureDrawAndGuessGame() throws -> RemoteEnsureGameResult {
        try begin("ensure")
        return RemoteEnsureGameResult(gameID: GameFixture.gameID, created: true)
    }

    func loadDrawAndGuess() throws -> RemoteDrawAndGuessState {
        try begin("load")
        guard let state = read(\.stateToLoad) else { throw Failure() }
        return state
    }

    func loadDrawAndGuessRound(roundID: UUID) throws -> RemoteDrawAndGuessRound? {
        try begin("loadRound")
        return read { $0.roundsToLoad[roundID] }
    }

    func pickWord(_ pick: GamePickWordPayload, operation _: SyncClientOperation) throws -> RemotePickedWord {
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
    ) throws -> RemoteSubmitDrawingResult {
        try begin("submitDrawing")
        if let error = read(\.submitError) { throw error }
        write { $0.submittedDrawings.append((roundID, mediaAssetID)) }
        return RemoteSubmitDrawingResult(roundID: roundID, roundState: .guessing, drawingSubmittedAt: GameFixture.now)
    }

    func markRoundSeen(roundID: UUID) throws -> RemoteMarkSeenResult {
        try begin("markSeen")
        write { $0.seenRounds.append(roundID) }
        return RemoteMarkSeenResult(guesserFirstSeenAt: GameFixture.now)
    }

    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID _: UUID,
        guess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation _: SyncClientOperation
    ) throws -> RemoteGuessResult {
        try begin("guess")
        if let error = read(\.guessError),
           !read(\.guessErrorOnlyWithClaim) || speedBonus != nil || solveMs != nil || hintsUsed != nil {
            throw error
        }
        write {
            $0.guesses.append(guess)
            $0.guessClaims.append(GuessClaim(speedBonus: speedBonus, solveMs: solveMs, hintsUsed: hintsUsed))
        }
        return RemoteGuessResult(
            guessID: UUID(),
            correct: false,
            roundState: .guessing,
            points: 0,
            speedBonus: 0,
            firstTryBonus: 0,
            hintsUsed: 0,
            personalBest: false,
            solveMs: nil,
            createdAt: GameFixture.now
        )
    }

    func giveUp(roundID: UUID, operation _: SyncClientOperation) throws -> RemoteGiveUpResult {
        try begin("giveUp")
        if let error = read(\.giveUpError) { throw error }
        return RemoteGiveUpResult(roundID: roundID, roundState: .missed)
    }

    func setRoundReaction(roundID: UUID, reaction: DrawAndGuessReaction?) throws -> RemoteReactionResult {
        try begin("reaction")
        if let error = read(\.reactionError) { throw error }
        write { $0.reactions.append(SentReaction(roundID: roundID, reaction: reaction)) }
        return RemoteReactionResult(roundID: roundID, guesserReaction: reaction)
    }

    func markRoundResultSeen(roundID: UUID) throws -> RemoteResultSeenResult {
        try begin("resultSeen")
        write { $0.resultSeenRounds.append(roundID) }
        return RemoteResultSeenResult(roundID: roundID, resultSeenAt: GameFixture.now)
    }

    // MARK: History and stars

    var historyRequests: [HistoryRequest] { read(\.historyRequests) }
    var starWrites: [StarWrite] { read(\.starWrites) }

    /// The rounds the history holds, newest first. The gateway pages them the way the server does.
    func setHistory(_ rounds: [RemoteDrawAndGuessHistoryRound]) {
        write { $0.historyRounds = rounds }
    }

    func setStarError(_ error: PaeoniaConvexError?) {
        write { $0.starError = error }
    }

    func setRecords(_ records: RemoteDrawAndGuessRecords?) {
        write { $0.recordsToLoad = records }
    }

    func loadDrawAndGuessHistory(
        starredOnly: Bool,
        beforeRoundNumber: Int?,
        limit: Int
    ) throws -> RemoteDrawAndGuessHistoryPage {
        let request = HistoryRequest(starredOnly: starredOnly, beforeRoundNumber: beforeRoundNumber, limit: limit)
        write { $0.historyRequests.append(request) }
        try begin("history")
        return DeveloperGamesFixture.historyPage(
            from: read(\.historyRounds),
            starredOnly: starredOnly,
            before: beforeRoundNumber,
            limit: limit
        )
    }

    func loadDrawAndGuessRecords() throws -> RemoteDrawAndGuessRecords {
        try begin("records")
        guard let records = read(\.recordsToLoad) else { throw Failure() }
        return records
    }

    func setRoundStar(roundID: UUID, starred: Bool) throws -> RemoteRoundStarResult {
        try begin("star")
        if let error = read(\.starError) { throw error }
        write { $0.starWrites.append(StarWrite(roundID: roundID, starred: starred)) }
        return RemoteRoundStarResult(roundID: roundID, starred: starred)
    }
}

/// The calls every game shares: the overview, invites and presence.
extension ScriptedGamesGateway {
    func sendInvite(_ kind: GameKind) throws -> RemoteInviteResult {
        try begin("invite")
        if let error = read(\.inviteError) { throw error }
        write {
            $0.inviteCount += 1
            $0.inviteKinds.append(kind)
        }
        return RemoteInviteResult(sentAt: GameFixture.now)
    }

    // swiftlint:disable:next async_without_await
    func setPresence(_ kind: GameKind, isPresent: Bool) async throws {
        write {
            $0.calls.append("presence")
            $0.presence.append(isPresent)
            $0.presenceKinds.append(kind)
        }
    }

    // The overview the state to load implies, so a test sets one value for both reads.
    // swiftlint:disable:next async_without_await
    func loadOverview() async throws -> RemoteGamesOverview {
        try begin("overview")
        return try overviewToLoad()
    }

    private func overviewToLoad() throws -> RemoteGamesOverview {
        guard let state = read(\.stateToLoad) else { throw Failure() }
        let overview = RemoteGamesOverview(drawAndGuess: state)
        guard read(\.settingsSeen), var settings = overview.settings else { return overview }
        settings.seenByUserIDs.append(GameFixture.me)
        return RemoteGamesOverview(
            userID: overview.userID,
            partnerUserID: overview.partnerUserID,
            coupleID: overview.coupleID,
            settings: settings,
            presence: overview.presence
        )
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
        parent: GameUploadParent,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) throws -> UUID {
        lock.withLock { recordedUploads.append((parent.id, data.count)) }
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

    init(state: RemoteDrawAndGuessState?) {
        cache = InMemoryGamesCache(state: state, ownerUserID: GameFixture.me)
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
@discardableResult
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
