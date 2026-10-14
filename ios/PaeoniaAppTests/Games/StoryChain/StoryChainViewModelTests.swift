import Foundation
import Testing
@testable import PaeoniaApp

/// A clock the tests move by hand.
final class StoryChainTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// A live connection that keeps the game messages sent on it and feeds the game
/// messages a test hands it, instead of opening a socket.
@MainActor
final class StoryChainRecordingConnection: WidgetLiveConnection {
    private(set) var sentGameData: [Data] = []

    init() {
        super.init(coupleID: UUID(), ticketProvider: { _ in nil })
    }

    override func start() {}

    override func stop() {}

    override func send(_: WidgetLiveMessage) {}

    override func send(gameData: Data) {
        sentGameData.append(gameData)
    }

    var sentMessages: [StoryChainLiveMessage] {
        sentGameData.compactMap {
            try? JSONDecoder().decode(GameLiveEnvelope<StoryChainLiveMessage>.self, from: $0).message
        }
    }

    /// The partner's phone sent this message.
    func receive(_ message: StoryChainLiveMessage) {
        let data = (try? JSONEncoder().encode(GameLiveEnvelope(game: StoryChainLiveMessage.game, message: message)))
        onGameData?(data ?? Data())
    }

    /// The partner joined the room and says what its screen shows.
    func partnerJoins(role: String) {
        onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role))
    }
}

/// Records the calls the Story Chain screen makes and answers with what a test sets.
final class ScriptedStoryChainGateway: StoryChainGateway, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var recorded: [String] = []
    private var stateToLoad: RemoteStoryChainState?
    private var failsEnsure = false

    var calls: [String] {
        lock.withLock { recorded }
    }

    func setStateToLoad(_ state: RemoteStoryChainState?) {
        lock.withLock { stateToLoad = state }
    }

    func setEnsureFails(_ fails: Bool) {
        lock.withLock { failsEnsure = fails }
    }

    private func record(_ call: String) {
        lock.withLock { recorded.append(call) }
    }

    // swiftlint:disable async_without_await
    func ensureStoryChainGame() async throws -> RemoteEnsureStoryChainResult {
        record("ensure")
        if lock.withLock({ failsEnsure }) {
            throw Failure()
        }
        return RemoteEnsureStoryChainResult(gameID: StoryChainFixture.gameID, created: true)
    }

    func loadStoryChain() async throws -> RemoteStoryChainState {
        record("load")
        guard let state = lock.withLock({ stateToLoad }) else {
            throw Failure()
        }
        return state
    }

    // The rest of the protocol is not used by the view model. Each call fails.
    func loadStory(id _: UUID) async throws -> RemoteStoryChainStory? {
        throw Failure()
    }

    func startStory(_: StoryChainQueuedStart, operation _: SyncClientOperation) async throws -> RemoteStartStoryResult {
        throw Failure()
    }

    func addStoryLine(
        _: StoryChainQueuedLine,
        operation _: SyncClientOperation
    ) async throws -> RemoteAddStoryLineResult {
        throw Failure()
    }

    func nameStory(_: StoryChainQueuedName, operation _: SyncClientOperation) async throws -> RemoteNameStoryResult {
        throw Failure()
    }

    func markStorySeen(storyID _: UUID) async throws {
        throw Failure()
    }

    func setStoryStar(storyID _: UUID, starred _: Bool) async throws -> RemoteStoryStarResult {
        throw Failure()
    }

    func loadStoryChainHistory(
        starredOnly _: Bool,
        beforeStoryNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteStoryChainHistoryPage {
        throw Failure()
    }

    func setSettings(playStyle _: GamePlayStyle, language _: GameLanguage) async throws -> RemoteGameSettings {
        throw Failure()
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        throw Failure()
    }

    func setPresence(_: GameKind, isPresent _: Bool) async throws {
        throw Failure()
    }

    func sendInvite(_: GameKind) async throws -> RemoteInviteResult {
        throw Failure()
    }
    // swiftlint:enable async_without_await
}

/// Everything a Story Chain test needs, in memory. The signed-in person is
/// `Fixture.me`, named Alex, and the partner is Robin.
@MainActor
struct StoryChainTestEnvironment {
    typealias Fixture = StoryChainFixture

    static let participants = GameParticipants(
        currentUserID: Fixture.me,
        coupleID: Fixture.couple,
        partnerName: "Robin",
        currentName: "Alex"
    )

    /// Presence and invites go through the shared Games gateway.
    let gateway = ScriptedGamesGateway()
    let storyGateway = ScriptedStoryChainGateway()
    let cache: InMemoryStoryChainCache
    let gamesCache: InMemoryGamesCache
    let pending = InMemoryPendingSyncOperationRepository()
    let operations = DeveloperScenarioOperationProvider()
    let clock = StoryChainTestClock(GameFixture.now)
    let connection = StoryChainRecordingConnection()
    let room: WidgetLiveDrawing

    init(
        state: RemoteStoryChainState?,
        settings: RemoteGameSettings? = Fixture.settings(),
        presence: [RemoteGamePresence] = []
    ) {
        cache = InMemoryStoryChainCache(state: state, ownerUserID: Fixture.me)
        gamesCache = InMemoryGamesCache(
            overview: RemoteGamesOverview(
                userID: Fixture.me,
                partnerUserID: Fixture.partner,
                coupleID: Fixture.couple,
                settings: settings,
                presence: presence
            ),
            ownerUserID: Fixture.me
        )
        room = WidgetLiveDrawing(
            connection: connection,
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }

    func dependencies() -> GamesDependencies {
        let room = room
        let clock = clock
        return GamesDependencies(
            gateway: gateway,
            cache: gamesCache,
            pendingOperationStore: pending,
            operationProvider: operations,
            drawingStore: InMemoryGameDrawingStore(),
            drawingTransfer: ScriptedDrawingTransfer(),
            makeLive: { _ in nil },
            now: { clock.now },
            storyChainGateway: storyGateway,
            storyChainCache: cache,
            makeStoryChainLive: { _ in room }
        )
    }

    /// The heartbeat and the tick sleep for an hour, so they stay out of the way.
    func viewModel(liveSendInterval: Duration = .milliseconds(30)) -> StoryChainViewModel {
        StoryChainViewModel(
            dependencies: dependencies(),
            participants: Self.participants,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600),
            liveSendInterval: liveSendInterval
        )
    }

    func hubModel() -> StoryChainHubModel {
        StoryChainHubModel(dependencies: dependencies())
    }

    /// The operations still waiting, by kind.
    func queued(_ kind: SyncPendingOperationKind) async -> [PendingSyncOperationSnapshot] {
        (try? await pending.inFlightOperations(ownerUserID: Fixture.me, kind: kind)) ?? []
    }

    func queuedLines() async -> [StoryChainQueuedLine] {
        await queued(.storyChainAddLine).compactMap { operation in
            operation.requestData.flatMap { try? JSONDecoder().decode(StoryChainQueuedLine.self, from: $0) }
        }
    }

    func queuedNames() async -> [StoryChainQueuedName] {
        await queued(.storyChainNameStory).compactMap { operation in
            operation.requestData.flatMap { try? JSONDecoder().decode(StoryChainQueuedName.self, from: $0) }
        }
    }

    func queuedStarts() async -> [StoryChainQueuedStart] {
        await queued(.storyChainStartStory).compactMap { operation in
            operation.requestData.flatMap { try? JSONDecoder().decode(StoryChainQueuedStart.self, from: $0) }
        }
    }

    func queuedSeenMarks() async -> [UUID] {
        await queued(.storyChainMarkSeen).compactMap { operation in
            operation.requestData
                .flatMap { try? JSONDecoder().decode(StoryChainSeenPayload.self, from: $0) }?.storyID
        }
    }

    // MARK: States

    static func line(
        _ number: Int,
        by author: UUID,
        text: String? = nil,
        dare: String? = nil,
        id: UUID = UUID()
    ) -> RemoteStoryLine {
        RemoteStoryLine(
            id: id,
            number: number,
            authorUserID: author,
            text: text ?? "Line \(number).",
            dareWord: dare,
            createdAt: Fixture.now.addingTimeInterval(Double(number) * 60)
        )
    }

    static func state(
        _ game: RemoteStoryChainGame?,
        current: RemoteStoryChainStory? = nil,
        previous: RemoteStoryChainStory? = nil,
        openings: [RemoteStoryOpening]? = nil,
        words: [RemoteStoryDareWord]? = nil
    ) -> RemoteStoryChainState {
        RemoteStoryChainState(
            userID: Fixture.me,
            partnerUserID: Fixture.partner,
            coupleID: Fixture.couple,
            game: game,
            currentStory: current,
            previousStory: previous,
            openingChoices: openings,
            wordChoices: words
        )
    }

    /// A story being written. `turn` writes the next line.
    static func writing(
        turn: UUID,
        lines: [RemoteStoryLine],
        opening: String? = nil,
        words: [RemoteStoryDareWord]? = nil,
        version: Int = 1
    ) -> RemoteStoryChainState {
        state(
            Fixture.game(.writing, turn: turn, version: version),
            current: Fixture.story(.writing, lines: lines, opening: opening),
            words: words
        )
    }

    /// The story is written to its last line and `turn` gives it a title.
    static func titling(turn: UUID, lines: [RemoteStoryLine]) -> RemoteStoryChainState {
        state(Fixture.game(.titling, turn: turn), current: Fixture.story(.titling, lines: lines))
    }

    /// The partner writes line 2 after my line 1.
    static func waitingOnPartner() -> StoryChainTestEnvironment {
        StoryChainTestEnvironment(state: writing(turn: Fixture.partner, lines: [line(1, by: Fixture.me)]))
    }

    /// I write line 2 after the partner's line 1.
    static func myTurnAfterPartner() -> StoryChainTestEnvironment {
        StoryChainTestEnvironment(state: writing(turn: Fixture.me, lines: [line(1, by: Fixture.partner)]))
    }

    /// My turn to start a story, with the openings the server offers.
    static func choosing(openings: [RemoteStoryOpening]?) -> StoryChainTestEnvironment {
        let game = Fixture.game(.choosingOpening, turn: Fixture.me, current: nil, stories: 0)
        return StoryChainTestEnvironment(state: state(game, openings: openings))
    }

    static let openings = [
        RemoteStoryOpening(openingID: "en-key", text: "A key opened nothing in town."),
        RemoteStoryOpening(openingID: "en-bus", text: "The last bus left without a driver."),
        RemoteStoryOpening(openingID: "en-cat", text: "Every cat on the street looked up at once."),
    ]

    static let words = [
        RemoteStoryDareWord(wordID: "en-lantern", word: "lantern"),
        RemoteStoryDareWord(wordID: "en-ladder", word: "ladder"),
        RemoteStoryDareWord(wordID: "en-harbor", word: "harbor"),
    ]
}

/// The phase, the page, the choices, and the partner's presence.
@MainActor
struct StoryChainViewModelTests {
    private typealias Fixture = StoryChainFixture
    private typealias Env = StoryChainTestEnvironment

    // MARK: Phase from the state

    @Test func theStateAndTheTurnPickThePhase() async {
        let mine = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let mineModel = mine.viewModel()
        await mineModel.reload()
        #expect(mineModel.phase == .writing)

        let theirs = Env(state: Env.writing(turn: Fixture.partner, lines: [Env.line(1, by: Fixture.me)]))
        let theirsModel = theirs.viewModel()
        await theirsModel.reload()
        #expect(theirsModel.phase == .waitingForLine)
    }

    @Test func nothingCachedIsLoadingAndNoSettingsIsSetup() async {
        let empty = Env(state: nil).viewModel()
        await empty.reload()
        #expect(empty.phase == .loading)

        let noSettings = Env(state: Env.state(nil), settings: nil).viewModel()
        await noSettings.reload()
        #expect(noSettings.phase == .needsSetup)
    }

    @Test func aMoveSavedOnThePhoneCountsBeforeTheServerHearsOfIt() async {
        let environment = Env(state: Env.writing(turn: Fixture.me, lines: [Env.line(1, by: Fixture.partner)]))
        let viewModel = environment.viewModel()
        await viewModel.reload()
        #expect(!viewModel.isWaitingToSend)

        viewModel.draft = "The door was open."
        await viewModel.sendLine()

        #expect(viewModel.phase == .waitingForLine)
        #expect(viewModel.isWaitingToSend)
        #expect(viewModel.page.lines.count == 2)
        #expect(viewModel.page.lines.last?.isMine == true)
    }

    // MARK: The page

    @Test func thePageHoldsTheOpeningAndEachLineWithItsWriter() async {
        let first = Env.line(1, by: Fixture.partner, text: "She took the night bus.", dare: "anchor")
        let second = Env.line(2, by: Fixture.me, text: "An anchor hung on the door.")
        let third = Env.line(3, by: Fixture.partner, text: "Nobody answered.")
        let viewModel = Env(state: Env.writing(
            turn: Fixture.me,
            lines: [first, second, third],
            opening: "A key opened nothing in town."
        )).viewModel()
        await viewModel.reload()

        #expect(viewModel.page.opening == "A key opened nothing in town.")
        #expect(viewModel.page.lines.map(\.id) == [first.id, second.id, third.id])
        #expect(viewModel.page.lines.map(\.number) == [1, 2, 3])
        #expect(viewModel.page.lines.map(\.isMine) == [false, true, false])
        #expect(viewModel.page.lines.map(\.authorName) == ["Robin", "Alex", "Robin"])
        // The second line used the word the first one dared.
        #expect(viewModel.page.lines.map(\.usedDare) == [nil, "anchor", nil])
    }

    @Test func aDareTheLineDoesNotContainIsNotUnderlined() async {
        let first = Env.line(1, by: Fixture.partner, dare: "anchor")
        let second = Env.line(2, by: Fixture.me, text: "Nothing about boats here.")
        let viewModel = Env(state: Env.writing(turn: Fixture.partner, lines: [first, second])).viewModel()
        await viewModel.reload()

        #expect(viewModel.page.lines.last?.usedDare == nil)
    }

    @Test func tappingALineShowsWhoWroteItAndWhen() async throws {
        let first = Env.line(1, by: Fixture.partner)
        let second = Env.line(2, by: Fixture.me, dare: nil)
        let viewModel = Env(state: Env.writing(turn: Fixture.partner, lines: [first, second])).viewModel()
        await viewModel.reload()

        let info = try #require(viewModel.lineInfo(for: first.id))
        #expect(info == StoryChainLineInfo(
            authorName: "Robin",
            isMine: false,
            createdAt: first.createdAt,
            usedDare: nil
        ))
        #expect(viewModel.lineInfo(for: second.id)?.isMine == true)
        #expect(viewModel.lineInfo(for: UUID()) == nil)
    }
}
