import Foundation
@testable import PaeoniaApp

// The fakes the Story Chain data tests share: a scripted gateway, an unreadable
// queue, and an environment that wires them into `GamesDependencies`. There are
// no tests in this file.

// The gateway protocol is async, and the fakes answer at once.
// swiftlint:disable async_without_await

/// Records every Story Chain call and fails the ones a test lists. A class with a
/// lock, so tests read its record without `await`.
final class ScriptedStoryChainDataGateway: StoryChainGateway, @unchecked Sendable {
    struct Failure: Error {}

    struct HistoryRequest: Equatable {
        var starredOnly: Bool
        var beforeStoryNumber: Int?
        var limit: Int
    }

    private struct Record {
        var calls: [String] = []
        var starts: [StoryChainQueuedStart] = []
        var lines: [StoryChainQueuedLine] = []
        var names: [StoryChainQueuedName] = []
        var seenStories: [UUID] = []
        var starredStoryIDs: Set<UUID> = []
        var historyRequests: [HistoryRequest] = []
        var failing: Set<String> = []
        var errors: [String: PaeoniaConvexError] = [:]
        var stateToLoad: RemoteStoryChainState?
        var storiesToLoad: [UUID: RemoteStoryChainStory] = [:]
        var history: [RemoteStoryChainHistoryItem] = []
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
    var starts: [StoryChainQueuedStart] { read(\.starts) }
    var lines: [StoryChainQueuedLine] { read(\.lines) }
    var names: [StoryChainQueuedName] { read(\.names) }
    var seenStories: [UUID] { read(\.seenStories) }
    /// The stories this person favorited, which the starred filter of the history returns.
    func setStarredStories(_ ids: Set<UUID>) {
        write { $0.starredStoryIDs = ids }
    }
    var historyRequests: [HistoryRequest] { read(\.historyRequests) }

    /// Fails the call with a plain error, the way a lost connection does.
    func fail(_ name: String) {
        write { $0.failing.insert(name) }
    }

    func unfail(_ name: String) {
        write { $0.failing.remove(name) }
    }

    /// Makes the call answer with a server error. Nil lets it succeed again.
    func setError(_ error: PaeoniaConvexError?, for name: String) {
        write { $0.errors[name] = error }
    }

    func setStateToLoad(_ state: RemoteStoryChainState?) {
        write { $0.stateToLoad = state }
    }

    /// What `loadStory` finds. A story not set here does not exist.
    func setStoryToLoad(_ story: RemoteStoryChainStory) {
        write { $0.storiesToLoad[story.id] = story }
    }

    /// The stories the history holds. The gateway pages them the way the server does.
    func setHistory(_ items: [RemoteStoryChainHistoryItem]) {
        write { $0.history = items }
    }

    private func begin(_ name: String) throws {
        let outcome: (any Error)? = lock.withLock {
            record.calls.append(name)
            if record.failing.contains(name) {
                return Failure()
            }
            return record.errors[name]
        }
        if let outcome {
            throw outcome
        }
    }

    // MARK: Story Chain

    func ensureStoryChainGame() async throws -> RemoteEnsureStoryChainResult {
        try begin("ensure")
        return RemoteEnsureStoryChainResult(gameID: StoryChainFixture.gameID, created: true)
    }

    func loadStoryChain() async throws -> RemoteStoryChainState {
        try begin("load")
        guard let state = read(\.stateToLoad) else { throw Failure() }
        return state
    }

    func loadStory(id: UUID) async throws -> RemoteStoryChainStory? {
        try begin("loadStory")
        return read { $0.storiesToLoad[id] }
    }

    func startStory(
        _ start: StoryChainQueuedStart,
        operation _: SyncClientOperation
    ) async throws -> RemoteStartStoryResult {
        try begin("start")
        write { $0.starts.append(start) }
        return RemoteStartStoryResult(storyID: start.storyID, storyNumber: 1)
    }

    func addStoryLine(
        _ line: StoryChainQueuedLine,
        operation _: SyncClientOperation
    ) async throws -> RemoteAddStoryLineResult {
        try begin("line")
        write { $0.lines.append(line) }
        return RemoteAddStoryLineResult(lineID: line.lineID, number: 1, storyState: line.isLast ? .titling : .writing)
    }

    func nameStory(
        _ name: StoryChainQueuedName,
        operation _: SyncClientOperation
    ) async throws -> RemoteNameStoryResult {
        try begin("name")
        write { $0.names.append(name) }
        return RemoteNameStoryResult(storyID: name.storyID, title: name.title)
    }

    func markStorySeen(storyID: UUID) async throws {
        try begin("seen")
        write { $0.seenStories.append(storyID) }
    }

    func loadStoryChainHistory(
        starredOnly: Bool,
        beforeStoryNumber: Int?,
        limit: Int
    ) async throws -> RemoteStoryChainHistoryPage {
        let request = HistoryRequest(starredOnly: starredOnly, beforeStoryNumber: beforeStoryNumber, limit: limit)
        write { $0.historyRequests.append(request) }
        try begin("history")
        let matching = read(\.history)
            .filter { !starredOnly || read(\.starredStoryIDs).contains($0.id) }
            .filter { item in beforeStoryNumber.map { item.storyNumber < $0 } ?? true }
            .sorted { $0.storyNumber > $1.storyNumber }
        let page = Array(matching.prefix(limit))
        let hasMore = matching.count > page.count
        return RemoteStoryChainHistoryPage(
            stories: page,
            nextBeforeStoryNumber: hasMore ? page.last?.storyNumber : nil
        )
    }

    // MARK: Shared Games calls, which these tests never use

    func setSettings(playStyle _: GamePlayStyle, language _: GameLanguage) async throws -> RemoteGameSettings {
        throw Failure()
    }

    func markSettingsSeen() async throws -> RemoteGameSettings {
        throw Failure()
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        throw Failure()
    }

    func setPresence(_: GameKind, isPresent _: Bool) async throws {}

    func sendInvite(_: GameKind) async throws -> RemoteInviteResult {
        throw Failure()
    }

    func hideWaitingGame(_: GameKind) async throws {
        throw Failure()
    }
}

/// A queue that cannot be read or written.
actor UnreadableStoryChainPendingStore: PendingSyncOperationPersisting {
    struct Failure: Error {}

    func enqueue(_: PendingSyncOperationRequest) async throws {
        throw Failure()
    }

    func readyOperations(
        ownerUserID _: UUID,
        limit _: Int,
        now _: Date
    ) async throws -> [PendingSyncOperationSnapshot] {
        throw Failure()
    }

    func nextPendingOperationDate(ownerUserID _: UUID, now _: Date) async throws -> Date? {
        throw Failure()
    }

    func inFlightOperations(
        ownerUserID _: UUID,
        kind _: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        throw Failure()
    }

    func markSending(clientOperationID _: UUID, at _: Date) async throws {
        throw Failure()
    }

    func markSucceeded(clientOperationID _: UUID, at _: Date) async throws {
        throw Failure()
    }

    func markRetryableFailure(
        clientOperationID _: UUID,
        errorDescription _: String,
        nextRetryAt _: Date?,
        at _: Date
    ) async throws {
        throw Failure()
    }

    func markTerminalFailure(clientOperationID _: UUID, errorDescription _: String, at _: Date) async throws {
        throw Failure()
    }

    func deleteCompleted(ownerUserID _: UUID) async throws {
        throw Failure()
    }

    func resetInFlight(ownerUserID _: UUID) async throws {
        throw Failure()
    }
}
// swiftlint:enable async_without_await

/// A finished story as "Our stories" lists it. The id follows the number.
func storyChainHistoryItem(_ number: Int) -> RemoteStoryChainHistoryItem {
    RemoteStoryChainHistoryItem(
        id: storyChainHistoryID(number),
        storyNumber: number,
        title: "Story \(number)",
        firstLine: "The first line of story \(number).",
        lineCount: 10,
        finishedAt: StoryChainFixture.now.addingTimeInterval(Double(number) * 3_600)
    )
}

/// The id of the history item with this number.
func storyChainHistoryID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "dddddddd-0000-4000-8000-%012d", number)) ?? UUID()
}

/// What the server answers when the phone reads the state after a move it took.
func storyChainStateAfterAMove() -> RemoteStoryChainState {
    StoryChainFixture.state(
        StoryChainFixture.game(.writing, turn: StoryChainFixture.partner, version: 7),
        current: StoryChainFixture.story(.writing, lines: StoryChainFixture.lines(3, starter: StoryChainFixture.me))
    )
}

/// A page of "Our stories" with the stories of these numbers, in the order given.
func storyChainHistoryPage(_ numbers: [Int], next: Int?) -> RemoteStoryChainHistoryPage {
    RemoteStoryChainHistoryPage(stories: numbers.map { storyChainHistoryItem($0) }, nextBeforeStoryNumber: next)
}

/// The state of a game that waits for the next story to start, right after `story` was named.
func finishedStoryChainState(_ story: RemoteStoryChainStory, version: Int = 1) -> RemoteStoryChainState {
    StoryChainFixture.state(
        StoryChainFixture.game(.choosingOpening, turn: StoryChainFixture.me, current: story.id, version: version),
        current: story
    )
}

/// A finished story, for a state.
func finishedStoryChainStory(
    id: UUID = StoryChainFixture.storyID,
    number: Int = 1
) -> RemoteStoryChainStory {
    StoryChainFixture.story(
        .finished,
        id: id,
        number: number,
        lines: StoryChainFixture.lines(8, starter: StoryChainFixture.partner),
        seenByMe: true
    )
}

/// Everything a Story Chain data test needs, in memory.
@MainActor
struct StoryChainDataEnvironment {
    let gateway = ScriptedStoryChainDataGateway()
    let cache: InMemoryStoryChainCache
    let gamesCache = InMemoryGamesCache()
    let pending: any PendingSyncOperationPersisting
    let operations = DeveloperScenarioOperationProvider()
    let clientID = UUID()

    init(
        state: RemoteStoryChainState? = nil,
        pending: any PendingSyncOperationPersisting = InMemoryPendingSyncOperationRepository()
    ) {
        cache = InMemoryStoryChainCache(state: state, ownerUserID: StoryChainFixture.me)
        self.pending = pending
        // The server answers the read that follows each move it takes.
        gateway.setStateToLoad(storyChainStateAfterAMove())
    }

    func dependencies(favorites: FavoritesStore = .inMemory()) -> GamesDependencies {
        GamesDependencies(
            gateway: UnavailableGamesGateway(),
            cache: gamesCache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: InMemoryGameDrawingStore(),
            drawingTransfer: UnavailableGameDrawingTransfer(),
            makeLive: { _ in nil },
            now: { StoryChainFixture.now },
            favorites: favorites,
            storyChainGateway: gateway,
            storyChainCache: cache
        )
    }

    func operation(_ sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(clientID: clientID, clientSequence: sequence, localCreatedAt: StoryChainFixture.now)
    }

    /// Queues a write the way the screens do, with a fixed place in the order.
    func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: StoryChainFixture.me,
                operation: operation(sequence),
                operationKind: kind,
                idempotencyScope: "story-chain",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    /// A write about to be sent, which is not in the queue.
    func snapshot(
        _ kind: SyncPendingOperationKind,
        _ payload: some Encodable,
        sequence: Int64
    ) throws -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: StoryChainFixture.me,
            operation: operation(sequence),
            operationKind: kind,
            idempotencyScope: "story-chain",
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

    var context: SyncContext {
        SyncContext(
            session: SyncSession(userID: StoryChainFixture.me),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pending
        )
    }

    func lineHandler() -> StoryChainLinePendingOperationHandler {
        StoryChainLinePendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache)
    }

    func startHandler() -> StoryChainStartPendingOperationHandler {
        StoryChainStartPendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache)
    }

    func nameHandler() -> StoryChainNamePendingOperationHandler {
        StoryChainNamePendingOperationHandler(gateway: gateway, cache: cache, gamesCache: gamesCache)
    }

    func seenHandler() -> StoryChainSeenPendingOperationHandler {
        StoryChainSeenPendingOperationHandler(gateway: gateway, cache: cache)
    }

    /// The writes still waiting, by kind.
    func queued(_ kind: SyncPendingOperationKind) async -> [PendingSyncOperationSnapshot] {
        (try? await pending.inFlightOperations(ownerUserID: StoryChainFixture.me, kind: kind)) ?? []
    }

    /// One run of the outbox with the Story Chain handlers.
    func drain() async {
        let stream = PendingSyncOperationDrainStream(
            handlers: StoryChainPendingOperations.handlers(gateway: gateway, cache: cache, gamesCache: gamesCache),
            retryPolicy: PendingSyncOperationRetryPolicy(baseDelaySeconds: 0)
        )
        try? await stream.push(context: context)
    }
}
