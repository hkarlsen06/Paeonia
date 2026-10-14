import Foundation
import Testing
@testable import PaeoniaApp

/// The partner side of Mind Meld: the open-screen heartbeat, what the status
/// line says, the typing message, and the invite.
@MainActor
struct MindMeldPartnerTests {
    private let fixtures = MindMeldFixtures()
    private let never: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3_600)) }

    private func environment(
        _ round: RemoteMindMeldRound,
        overview: RemoteGamesOverview? = nil
    ) -> MindMeldTestEnvironment {
        MindMeldTestEnvironment(
            state: fixtures.state(current: fixtures.game(rounds: [round])),
            overview: overview
        )
    }

    private func room() -> (room: WidgetLiveDrawing, connection: GameDataRecordingConnection) {
        let connection = GameDataRecordingConnection()
        let room = WidgetLiveDrawing(
            connection: connection,
            role: .present,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
        return (room, connection)
    }

    /// The partner joins the relay room and says hello.
    private func partnerJoins(_ connection: GameDataRecordingConnection) {
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "present"))
    }

    private func partnerSays(_ message: MindMeldLiveMessage, on connection: GameDataRecordingConnection) throws {
        let envelope = GameLiveEnvelope(game: MindMeldLiveMessage.game, message: message)
        connection.onGameData?(try JSONEncoder().encode(envelope))
    }

    private func sent(_ connection: GameDataRecordingConnection) -> [MindMeldLiveMessage] {
        connection.sentGameData.compactMap {
            try? JSONDecoder().decode(GameLiveEnvelope<MindMeldLiveMessage>.self, from: $0).message
        }
    }

    // MARK: Heartbeat

    @Test func theScreenSaysItIsOpenNowAndGoneWhenItCloses() async {
        let env = environment(fixtures.open(1))
        let viewModel = env.viewModel(heartbeat: .seconds(30), sleep: never)

        await viewModel.start()
        let opened = await waitUntil { env.gamesGateway.presence == [true] }
        viewModel.stop()
        let closed = await waitUntil { env.gamesGateway.presence == [true, false] }

        #expect(opened)
        #expect(closed)
        #expect(env.gamesGateway.presenceKinds.allSatisfy { $0 == .mindMeld })
    }

    @Test func goingToTheBackgroundClosesPresenceAndComingBackOpensIt() async {
        let env = environment(fixtures.open(1))
        let viewModel = env.viewModel(heartbeat: .seconds(30), sleep: never)
        await viewModel.start()
        _ = await waitUntil { env.gamesGateway.presence == [true] }

        viewModel.scenePhaseChanged(isActive: false)
        let away = await waitUntil { env.gamesGateway.presence == [true, false] }
        viewModel.scenePhaseChanged(isActive: true)
        let back = await waitUntil { env.gamesGateway.presence == [true, false, true] }
        viewModel.stop()

        #expect(away)
        #expect(back)
    }

    // MARK: Status

    @Test func aFreshHeartbeatMeansThePartnerIsHere() async {
        let fresh = MindMeldTestEnvironment.overview(partnerLastSeenAt: GameFixture.now.addingTimeInterval(-10))
        let stale = MindMeldTestEnvironment.overview(partnerLastSeenAt: GameFixture.now.addingTimeInterval(-120))
        let here = environment(fixtures.open(1), overview: fresh).viewModel()
        let away = environment(fixtures.open(1), overview: stale).viewModel()
        let unknown = environment(fixtures.open(1)).viewModel()

        for viewModel in [here, away, unknown] {
            await viewModel.reload()
        }

        #expect(here.partnerStatus == .here)
        #expect(away.partnerStatus == .away)
        #expect(unknown.partnerStatus == .away)
    }

    @Test func aLockedWordBeatsEveryOtherStatus() async throws {
        let locked = fixtures.open(1, partnerLocked: true)
        let (room, connection) = room()
        let viewModel = environment(locked).viewModel(live: room)
        await viewModel.reload()
        #expect(viewModel.partnerStatus == .locked)

        partnerJoins(connection)
        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: true), on: connection)
        await viewModel.reload()
        #expect(viewModel.partnerStatus == .locked)
    }

    @Test func aRevealedRoundShowsNoLockedStatus() async {
        let env = MindMeldTestEnvironment(
            state: fixtures.state(current: fixtures.game(rounds: [fixtures.revealed(1, seen: false), fixtures.open(2)]))
        )
        let viewModel = env.viewModel()
        await viewModel.reload()

        #expect(viewModel.phase == .reveal)
        #expect(viewModel.partnerStatus == .away)
    }

    @Test func thePartnerInTheLiveRoomIsHereAndTypingShowsForTheOpenRound() async throws {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(1)).viewModel(live: room)
        await viewModel.reload()
        #expect(viewModel.partnerStatus == .away)

        partnerJoins(connection)
        await viewModel.reload()
        #expect(viewModel.partnerStatus == .here)

        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: true), on: connection)
        #expect(viewModel.partnerStatus == .typing)

        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: false), on: connection)
        #expect(viewModel.partnerStatus == .here)
    }

    @Test func aTypingMessageForAnotherRoundIsIgnored() async throws {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(2)).viewModel(live: room)
        partnerJoins(connection)
        await viewModel.reload()

        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: true), on: connection)
        #expect(viewModel.partnerStatus == .here)

        // A "stopped typing" for a round that is over does not stop typing in this one.
        try partnerSays(MindMeldLiveMessage(roundNumber: 2, isTyping: true), on: connection)
        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: false), on: connection)
        #expect(viewModel.partnerStatus == .typing)
    }

    @Test func typingStopsShowingWithoutANewTypingMessage() async throws {
        let (room, connection) = room()
        let viewModel = MindMeldViewModel(
            dependencies: environment(fixtures.open(1)).dependencies(live: room),
            participants: GameFixture.participants,
            typingTimeout: .milliseconds(20)
        )
        partnerJoins(connection)
        await viewModel.reload()

        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: true), on: connection)
        #expect(viewModel.partnerStatus == .typing)

        let cleared = await waitUntil { viewModel.partnerStatus == .here }
        #expect(cleared)
    }

    @Test func typingStopsShowingWhenThePartnerLeavesTheRoom() async throws {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(1)).viewModel(live: room)
        partnerJoins(connection)
        await viewModel.reload()
        try partnerSays(MindMeldLiveMessage(roundNumber: 1, isTyping: true), on: connection)
        #expect(viewModel.partnerStatus == .typing)

        connection.onMessage?(WidgetLiveMessage(type: .left, id: "partner"))
        await viewModel.reload()

        #expect(viewModel.partnerStatus == .away)
    }

    // MARK: Sending the typing state

    @Test func typingIsSentWhenItStartsAndWhenItStops() async {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(1)).viewModel(live: room, sleep: never)
        await viewModel.reload()

        viewModel.draft = "oc"
        viewModel.draft = "oce"
        #expect(sent(connection) == [MindMeldLiveMessage(roundNumber: 1, isTyping: true)])

        viewModel.draft = ""
        #expect(sent(connection) == [
            MindMeldLiveMessage(roundNumber: 1, isTyping: true),
            MindMeldLiveMessage(roundNumber: 1, isTyping: false),
        ])
    }

    @Test func typingStopsAfterAMomentWithoutChanges() async {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(1)).viewModel(live: room, sleep: { _ in await Task.yield() })
        await viewModel.reload()

        viewModel.draft = "oc"

        let stopped = await waitUntil { sent(connection).last?.isTyping == false }
        #expect(stopped)
    }

    @Test func lockingInSendsThatTypingStopped() async {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(1)).viewModel(live: room, sleep: never)
        await viewModel.reload()
        viewModel.draft = "ocean"

        viewModel.lockIn()

        #expect(sent(connection).last == MindMeldLiveMessage(roundNumber: 1, isTyping: false))
    }

    @Test func theTypingStateIsSentAgainWhenThePartnerArrives() async {
        let (room, connection) = room()
        let viewModel = environment(fixtures.open(1)).viewModel(live: room, sleep: never)
        await viewModel.reload()
        viewModel.draft = "ocean"
        #expect(sent(connection).count == 1)

        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))

        #expect(sent(connection) == Array(repeating: MindMeldLiveMessage(roundNumber: 1, isTyping: true), count: 2))
    }

    @Test func aMessageCarriesNoLettersAndIsTaggedWithTheGame() throws {
        let message = MindMeldLiveMessage(roundNumber: 3, isTyping: true)
        let data = try JSONEncoder().encode(GameLiveEnvelope(game: MindMeldLiveMessage.game, message: message))
        let text = try #require(String(bytes: data, encoding: .utf8))

        #expect(MindMeldLiveMessage.game == "mind_meld")
        #expect(text.contains("\"mind_meld\""))
        #expect(!text.contains("word"))
        #expect(GameLiveEnvelopeTag.isGameMessage(data, decoder: JSONDecoder()))
    }

    // MARK: Invite

    @Test func theInviteIsOfferedWhenThePartnerIsAwayAndHiddenWhenTheyAreHere() async {
        let away = environment(fixtures.open(1)).viewModel()
        let here = environment(
            fixtures.open(1),
            overview: MindMeldTestEnvironment.overview(partnerLastSeenAt: GameFixture.now.addingTimeInterval(-5))
        ).viewModel()
        let sentRecently = environment(
            fixtures.open(1),
            overview: MindMeldTestEnvironment.overview(lastInviteAt: GameFixture.now.addingTimeInterval(-60))
        ).viewModel()

        for viewModel in [away, here, sentRecently] {
            await viewModel.reload()
        }

        #expect(away.invite == .available)
        #expect(here.invite == .hidden)
        #expect(sentRecently.invite == .sent(until: GameFixture.now.addingTimeInterval(-60 + GameInviteState.interval)))
    }

    @Test func sendingAnInviteTellsTheServerAndShowsSent() async {
        let env = environment(fixtures.open(1))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(env.gamesGateway.inviteKinds == [.mindMeld])
        #expect(viewModel.invite == .sent(until: GameFixture.now.addingTimeInterval(GameInviteState.interval)))
        #expect(viewModel.notice == nil)

        // The button is gone for 15 minutes, so a second tap sends nothing.
        await viewModel.sendInvite()
        #expect(env.gamesGateway.inviteCount == 1)
    }

    @Test func anInviteTheServerAlreadyCountedStaysSent() async {
        let env = environment(fixtures.open(1))
        env.gamesGateway.setInviteError(PaeoniaConvexError.server(code: "53300", message: "too many invites"))
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        if case .sent = viewModel.invite {} else { Issue.record("The invite should read as sent") }
        #expect(viewModel.notice == nil)
    }

    @Test func aFailedInviteComesBackWithANotice() async {
        let env = environment(fixtures.open(1))
        env.gamesGateway.setInviteError(ScriptedGamesGateway.Failure())
        let viewModel = env.viewModel()
        await viewModel.reload()

        await viewModel.sendInvite()

        #expect(viewModel.invite == .available)
        #expect(viewModel.notice == .couldNotSendInvite)
    }
}
