import Foundation
import Testing
@testable import PaeoniaApp

/// What the partner is really doing: the role each phone announces, how the
/// screens read the partner's role, and the hand-off from a result to the next drawing.
@MainActor
struct DrawAndGuessPresenceTests {
    private func environment(_ state: RemoteDrawAndGuessState) -> GamesTestEnvironment {
        GamesTestEnvironment(state: state)
    }

    private func pick(turn: UUID, choices: [RemoteDrawAndGuessChoice]? = GameFixture.choices) -> RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: turn, roundID: nil),
            choices: choices
        )
    }

    /// Robin solved the drawing and has already started the next one.
    private var partnerDrawsNext: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me, roundID: GameFixture.nextRoundID),
            round: GameFixture.round(id: GameFixture.nextRoundID, state: .drawing, drawer: GameFixture.partner),
            recentRounds: [
                GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000),
            ]
        )
    }

    private func announcedRole(for state: RemoteDrawAndGuessState) async -> WidgetLivePresence.Role {
        let (room, _) = makeOfflineLiveRoom()
        let viewModel = environment(state).viewModel(live: room)
        await viewModel.reload()
        return room.role
    }

    // MARK: The role this phone announces

    @Test func eachPhaseAnnouncesWhatTheScreenIsDoing() async {
        #expect(await announcedRole(for: pick(turn: GameFixture.me)) == .choosing)
        #expect(await announcedRole(for: pick(turn: GameFixture.partner)) == .present)

        let drawing = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
        )
        #expect(await announcedRole(for: drawing) == .drawing)

        let waitingForDrawing = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        #expect(await announcedRole(for: waitingForDrawing) == .watching)

        let guessing = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
        #expect(await announcedRole(for: guessing) == .watching)
    }

    @Test func theDrawerStaysDrawingAfterDoneAndGoesToResultWhenTheRoundEnds() async {
        let sent = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        )
        #expect(await announcedRole(for: sent) == .drawing)

        let solved = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000)
        )
        #expect(await announcedRole(for: solved) == .result)
    }

    @Test func theGuesserLooksAtTheResultAsResult() async {
        let solved = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me),
            round: GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true, solveMs: 9_000),
            choices: GameFixture.choices
        )
        #expect(await announcedRole(for: solved) == .result)
    }

    // MARK: What this phone reads from the partner

    @Test func thePartnersRoleDecidesWhatTheScreenSays() async {
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = environment(pick(turn: GameFixture.partner)).viewModel(live: room)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))

        let expected: [(String, DrawAndGuessPartnerPresence)] = [
            ("present", .here),
            ("result", .result),
            ("choosing", .choosing),
            ("watching", .watching),
            ("drawing", .drawing),
        ]
        for (role, presence) in expected {
            connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role))
            viewModel.recompute()
            #expect(viewModel.partnerPresence == presence)
        }

        connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        viewModel.recompute()
        #expect(viewModel.partnerPresence == .away)
    }

    @Test func onlyAWatchingPartnerIsWatching() {
        #expect(DrawAndGuessPartnerPresence.watching.drawingLine(partnerName: "R") == .gamesDrawAndGuessDrawWatching("R"))
        #expect(DrawAndGuessPartnerPresence.result.drawingLine(partnerName: "R") == .gamesDrawAndGuessDrawLookingAtResult("R"))
        #expect(DrawAndGuessPartnerPresence.here.drawingLine(partnerName: "R") == .gamesDrawAndGuessDrawHere("R"))
        #expect(DrawAndGuessPartnerPresence.away.drawingLine(partnerName: "R") == .gamesDrawAndGuessDrawLater("R"))
        #expect(DrawAndGuessPartnerPresence.result.isHere)
        #expect(!DrawAndGuessPartnerPresence.away.isHere)
    }

    // MARK: The sent drawing

    @Test func theSentLineHasThreeStates() {
        let seen = Date(timeIntervalSince1970: 1)
        #expect(DrawAndGuessSentStatus.make(partner: .watching, guesserFirstSeenAt: nil) == .looking)
        #expect(DrawAndGuessSentStatus.make(partner: .watching, guesserFirstSeenAt: seen) == .looking)
        #expect(DrawAndGuessSentStatus.make(partner: .away, guesserFirstSeenAt: seen) == .seen)
        #expect(DrawAndGuessSentStatus.make(partner: .result, guesserFirstSeenAt: seen) == .seen)
        #expect(DrawAndGuessSentStatus.make(partner: .away, guesserFirstSeenAt: nil) == .notSeen)
        // Still on the last result, or just in the game: the drawing has not been seen.
        #expect(DrawAndGuessSentStatus.make(partner: .result, guesserFirstSeenAt: nil) == .notSeen)
        #expect(DrawAndGuessSentStatus.make(partner: .here, guesserFirstSeenAt: nil) == .notSeen)
    }

    @Test func theDrawerSeesLookingThenSeenWhenThePartnerLeavesTheGuessScreen() async {
        let sent = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true, guesserHasSeenIt: true)
        )
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = environment(sent).viewModel(live: room)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "watching"))
        viewModel.recompute()
        #expect(viewModel.sentStatus == .looking)

        connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        viewModel.recompute()
        #expect(viewModel.sentStatus == .seen)
    }

    @Test func aDrawingTheGuesserNeverOpenedStaysNotSeen() async {
        let sent = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        )
        let viewModel = environment(sent).viewModel()
        await viewModel.reload()

        #expect(viewModel.sentStatus == .notSeen)
    }

    // MARK: Watch the partner draw

    @Test func theResultOffersWatchingWhenThePartnerAlreadyDrawsTheNextRound() async {
        let env = environment(partnerDrawsNext)
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.round?.id == GameFixture.roundID)
        #expect(viewModel.partnerStartedDrawing)

        // Tapping the button acknowledges the result, which is a "not now" to saving.
        await viewModel.continueFromReveal()

        #expect(!viewModel.partnerStartedDrawing)
        #expect(viewModel.phase == .waitingForDrawing)
        #expect(viewModel.round?.id == GameFixture.nextRoundID)
    }

    @Test func aPlainResultKeepsTheNormalButton() async {
        let solved = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me, hasDrawing: true, solveMs: 9_000)
        )
        let viewModel = environment(solved).viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(!viewModel.partnerStartedDrawing)
    }

    // MARK: No offline flash

    @Test func theOfflineMessageNeverShowsWhileThePickHandsOffToDrawing() async throws {
        let env = environment(pick(turn: GameFixture.me))
        let viewModel = env.viewModel()
        await viewModel.reload()
        #expect(viewModel.phase == .chooseWord)
        #expect(!viewModel.choicesUnavailable)

        // The pick is queued: the phase is drawing and the word list is gone.
        await viewModel.chooseWord(try #require(viewModel.choices.first { $0.difficulty == .medium }))
        #expect(viewModel.phase == .drawing)
        #expect(viewModel.choices.isEmpty)
        #expect(!viewModel.choicesUnavailable)

        // The server has the round, and the queued pick is gone.
        await env.cache.saveState(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
                round: GameFixture.round(state: .drawing, drawer: GameFixture.me)
            ),
            ownerUserID: GameFixture.me
        )
        await viewModel.reload()
        #expect(viewModel.phase == .drawing)
        #expect(!viewModel.choicesUnavailable)
    }

    @Test func theOfflineMessageShowsWhenTheTurnIsMineAndNoWordsCame() async {
        let viewModel = environment(pick(turn: GameFixture.me, choices: nil)).viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .chooseWord)
        #expect(viewModel.choicesUnavailable)
    }
}
