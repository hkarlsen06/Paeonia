import Foundation
import Testing
@testable import PaeoniaApp

/// Builders for the data-layer tests: the resolver fixtures for the signed-in
/// person (`GameFixture.me`), and states with the same game at another version.
struct MindMeldFixtures: MindMeldResolverFixtures {
    let me = GameFixture.me
    let partner = GameFixture.partner

    /// `game` at another version and with other rounds, as the server would send it after a move.
    func moved(
        _ game: RemoteMindMeldGame,
        rounds: [RemoteMindMeldRound]? = nil,
        version: Int,
        state: MindMeldGameState? = nil
    ) -> RemoteMindMeldGame {
        RemoteMindMeldGame(
            id: game.id,
            gameNumber: game.gameNumber,
            state: state ?? game.state,
            endReason: game.endReason,
            endedByUserID: game.endedByUserID,
            endedAt: game.endedAt,
            maxRounds: game.maxRounds,
            myEndSeenAt: game.myEndSeenAt,
            meldNumber: game.meldNumber,
            isRecord: game.isRecord,
            createdByUserID: game.createdByUserID,
            createdAt: game.createdAt,
            updatedAt: game.updatedAt,
            version: version,
            rounds: rounds ?? game.rounds
        )
    }

    /// The environment for a state whose current game is `game`.
    @MainActor
    func environment(
        _ game: RemoteMindMeldGame?,
        previous: RemoteMindMeldGame? = nil,
        overview: RemoteGamesOverview? = nil
    ) -> MindMeldTestEnvironment {
        MindMeldTestEnvironment(state: state(current: game, previous: previous), overview: overview)
    }

    /// A melded game whose only round was a match.
    func meldedGame(seen: Bool) -> RemoteMindMeldGame {
        game(
            .melded,
            rounds: [revealed(1, "fish", "fish", outcome: .match, seen: seen)],
            endSeen: seen
        )
    }

    func historyGame(
        number: Int,
        state: MindMeldGameState = .melded,
        rounds: [RemoteMindMeldHistoryRound] = []
    ) -> RemoteMindMeldHistoryGame {
        RemoteMindMeldHistoryGame(
            id: UUID(),
            gameNumber: number,
            state: state,
            endReason: state == .ended ? .rounds : nil,
            endedByUserID: nil,
            createdAt: at,
            endedAt: at,
            meldNumber: state == .melded ? number : nil,
            rounds: rounds
        )
    }
}

/// Reads the payload of a queued write.
func decodePayload<Payload: Decodable>(_: Payload.Type, _ snapshot: PendingSyncOperationSnapshot?) throws -> Payload {
    try JSONDecoder().decode(Payload.self, from: try #require(snapshot?.requestData))
}

// The protocol is async, and the stand-in answers at once.
// swiftlint:disable async_without_await

/// Records every Mind Meld call and fails the ones a test lists. A class with a
/// lock, so tests read its record without `await`.
final class ScriptedMindMeldGateway: MindMeldGateway, @unchecked Sendable {
    struct Failure: Error {}

    struct Lock: Equatable {
        var roundID: UUID
        var word: String
    }

    struct HistoryRequest: Equatable {
        var beforeGameNumber: Int?
        var limit: Int
    }

    private struct Record {
        var calls: [String] = []
        var locks: [Lock] = []
        var counts: [UUID] = []
        var revealsSeen: [UUID] = []
        var endsSeen: [UUID] = []
        var restarts: [UUID] = []
        var starts = 0
        var failing: Set<String> = []
        var lockError: PaeoniaConvexError?
        var markError: PaeoniaConvexError?
        var stateToLoad: RemoteMindMeldState?
        var stateAfterStart: RemoteMindMeldState?
        var history: [RemoteMindMeldHistoryGame] = []
        var historyRequests: [HistoryRequest] = []
        var stats = RemoteMindMeldStats(melds: 0, fewestRounds: nil, games: 0)
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
    var locks: [Lock] { read(\.locks) }
    var counts: [UUID] { read(\.counts) }
    var revealsSeen: [UUID] { read(\.revealsSeen) }
    var endsSeen: [UUID] { read(\.endsSeen) }
    var restarts: [UUID] { read(\.restarts) }
    var starts: Int { read(\.starts) }
    var historyRequests: [HistoryRequest] { read(\.historyRequests) }

    func fail(_ name: String) {
        write { $0.failing.insert(name) }
    }

    func unfail(_ name: String) {
        write { $0.failing.remove(name) }
    }

    func setLockError(_ error: PaeoniaConvexError?) {
        write { $0.lockError = error }
    }

    /// Refuses counts and seen marks.
    func setMarkError(_ error: PaeoniaConvexError?) {
        write { $0.markError = error }
    }

    func setStateToLoad(_ state: RemoteMindMeldState?) {
        write { $0.stateToLoad = state }
    }

    /// What the next read returns once `startMindMeldGame` or `restartMindMeld` ran.
    func setStateAfterStart(_ state: RemoteMindMeldState?) {
        write { $0.stateAfterStart = state }
    }

    /// The finished games, newest first. The gateway pages them the way the server does.
    func setHistory(_ games: [RemoteMindMeldHistoryGame]) {
        write { $0.history = games }
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

    func loadMindMeld() async throws -> RemoteMindMeldState {
        try begin("load")
        guard let state = read(\.stateToLoad) else { throw Failure() }
        return state
    }

    func startMindMeldGame() async throws -> RemoteMindMeldStartResult {
        try begin("start")
        write {
            $0.starts += 1
            if let next = $0.stateAfterStart {
                $0.stateToLoad = next
            }
        }
        return RemoteMindMeldStartResult(gameID: UUID(), created: true)
    }

    func lockMindMeldWord(
        roundID: UUID,
        word: String,
        operation _: SyncClientOperation
    ) async throws -> RemoteMindMeldLockResult {
        try begin("lock")
        if let error = read(\.lockError) { throw error }
        write { $0.locks.append(Lock(roundID: roundID, word: word)) }
        return RemoteMindMeldLockResult(
            roundID: roundID,
            roundState: .open,
            outcome: nil,
            gameState: .playing,
            lockedAt: GameFixture.now
        )
    }

    func countMindMeldRound(roundID: UUID) async throws -> RemoteMindMeldCountResult {
        try begin("count")
        if let error = read(\.markError) { throw error }
        write { $0.counts.append(roundID) }
        return RemoteMindMeldCountResult(roundID: roundID, gameID: UUID(), gameState: .melded)
    }

    func markMindMeldRevealSeen(roundID: UUID) async throws -> RemoteMindMeldRevealSeenResult {
        try begin("revealSeen")
        if let error = read(\.markError) { throw error }
        write { $0.revealsSeen.append(roundID) }
        return RemoteMindMeldRevealSeenResult(roundID: roundID, revealSeenAt: GameFixture.now)
    }

    func markMindMeldEndSeen(gameID: UUID) async throws -> RemoteMindMeldEndSeenResult {
        try begin("endSeen")
        if let error = read(\.markError) { throw error }
        write { $0.endsSeen.append(gameID) }
        return RemoteMindMeldEndSeenResult(gameID: gameID, endSeenAt: GameFixture.now)
    }

    func restartMindMeld(gameID: UUID) async throws -> RemoteMindMeldStartResult {
        try begin("restart")
        write {
            $0.restarts.append(gameID)
            if let next = $0.stateAfterStart {
                $0.stateToLoad = next
            }
        }
        return RemoteMindMeldStartResult(gameID: UUID(), created: true)
    }

    func loadMindMeldHistory(beforeGameNumber: Int?, limit: Int) async throws -> RemoteMindMeldHistoryPage {
        write { $0.historyRequests.append(HistoryRequest(beforeGameNumber: beforeGameNumber, limit: limit)) }
        try begin("history")
        let finished = read(\.history).filter { $0.gameNumber < (beforeGameNumber ?? Int.max) }
        let games = Array(finished.prefix(limit))
        return RemoteMindMeldHistoryPage(
            games: games,
            nextBeforeGameNumber: finished.count > limit ? games.last?.gameNumber : nil,
            stats: read(\.stats)
        )
    }
}

// swiftlint:enable async_without_await

/// Everything a Mind Meld test needs, in memory.
@MainActor
struct MindMeldTestEnvironment {
    let fixtures = MindMeldFixtures()
    let gateway = ScriptedMindMeldGateway()
    let cache: InMemoryMindMeldCache
    let gamesGateway = ScriptedGamesGateway()
    let gamesCache: InMemoryGamesCache
    let pending = InMemoryPendingSyncOperationRepository()
    let operations = DeveloperScenarioOperationProvider()

    /// The server state the cache starts with. The scripted gateway answers reads with
    /// the same state, so a refresh keeps it.
    init(state: RemoteMindMeldState?, overview: RemoteGamesOverview? = nil) {
        cache = InMemoryMindMeldCache(state: state, ownerUserID: GameFixture.me)
        gamesCache = InMemoryGamesCache(overview: overview, ownerUserID: GameFixture.me)
        gateway.setStateToLoad(state)
    }

    /// The shared Games overview with the game language and, for Mind Meld, the
    /// partner's presence and this person's last invite.
    static func overview(
        language: GameLanguage = .en,
        partnerPresent: Bool = false,
        lastInviteAt: Date? = nil
    ) -> RemoteGamesOverview {
        RemoteGamesOverview(
            userID: GameFixture.me,
            partnerUserID: GameFixture.partner,
            coupleID: DeveloperScenarioFixture.coupleID,
            settings: RemoteGameSettings(
                coupleID: DeveloperScenarioFixture.coupleID,
                playStyle: .together,
                language: language,
                updatedByUserID: GameFixture.me,
                createdAt: GameFixture.now,
                updatedAt: GameFixture.now
            ),
            presence: [
                RemoteGamePresence(
                    kind: .mindMeld,
                    myPresent: false,
                    partnerPresent: partnerPresent,
                    lastInviteAt: lastInviteAt
                ),
            ]
        )
    }

    func dependencies(live: WidgetLiveDrawing? = nil) -> GamesDependencies {
        GamesDependencies(
            gateway: gamesGateway,
            cache: gamesCache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: InMemoryGameDrawingStore(),
            drawingTransfer: ScriptedDrawingTransfer(),
            makeLive: { _ in nil },
            now: { GameFixture.now },
            mindMeldGateway: gateway,
            mindMeldCache: cache,
            makeMindMeldLive: { _ in live }
        )
    }

    func viewModel(
        live: WidgetLiveDrawing? = nil,
        heartbeat: Duration = .seconds(3_600),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> MindMeldViewModel {
        MindMeldViewModel(
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

    /// Queues a write the way the view model does, with the order of `sequence`.
    func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: SyncClientOperation(
                    clientID: UUID(),
                    clientSequence: sequence,
                    localCreatedAt: GameFixture.now
                ),
                operationKind: kind,
                idempotencyScope: "mind-meld",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    /// Runs `handler` on a write made at `sequence`, with this environment's queue.
    func send(
        _ handler: some PendingSyncOperationHandling,
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        sequence: Int64 = 5
    ) async throws -> PendingSyncOperationSendResult {
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: GameFixture.now)
        return try await handler.send(
            try snapshot(kind, payload, operation: operation),
            context: syncContext(pending)
        )
    }

    /// The words the server refused for good, taken from the cache.
    func refusedWords() async -> [MindMeldRefusedWord] {
        await cache.takeRefusedWords(ownerUserID: GameFixture.me)
    }
}
