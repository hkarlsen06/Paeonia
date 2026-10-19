import Foundation
import Testing
@testable import PaeoniaApp

/// A clock the test moves by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = GameFixture.now

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// The guess carries what the player saw: the speed bonus tier on screen (2
/// within 15 seconds, 1 within 30, else 0), how long they had looked at the
/// drawing on the phone's clock, and how many letter hints they used.
@MainActor
struct DrawAndGuessSpeedBonusClaimTests {
    private let clock = ManualClock()
    private let env = GamesTestEnvironment(state: nil)

    private func makeEnvironment(_ state: RemoteDrawAndGuessState) -> GamesTestEnvironment {
        GamesTestEnvironment(state: state)
    }

    private func makeViewModel(
        _ environment: GamesTestEnvironment,
        live: WidgetLiveDrawing? = nil
    ) -> DrawAndGuessViewModel {
        var dependencies = environment.dependencies(live: live)
        let clock = clock
        dependencies.now = { clock.now }
        return DrawAndGuessViewModel(
            dependencies: dependencies,
            participants: GameFixture.participants,
            heartbeatInterval: .seconds(3_600),
            tickInterval: .seconds(3_600)
        )
    }

    private var guessing: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
    }

    private func type(_ word: String, into viewModel: DrawAndGuessViewModel) throws {
        for letter in word.uppercased() where letter != " " {
            let used = viewModel.slots.placedTileIDs
            let tile = try #require(viewModel.tiles.first { $0.letter == letter && !used.contains($0.id) })
            viewModel.placeTile(tile)
        }
    }

    private func queuedGuess(_ environment: GamesTestEnvironment) async throws -> GameGuessPayload {
        var queued: [PendingSyncOperationSnapshot] = []
        for _ in 0..<200 {
            queued = await environment.queued(.submitGameGuess)
            if !queued.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return try JSONDecoder().decode(GameGuessPayload.self, from: try #require(queued.first?.requestData))
    }

    @Test func aCorrectGuessInsideTheWindowClaimsTheBonusAndTheSolveTime() async throws {
        let environment = makeEnvironment(guessing)
        let viewModel = makeViewModel(environment)
        await viewModel.reload()
        let seen = await waitUntil { viewModel.localFirstSeenAt[GameFixture.roundID] != nil }
        #expect(seen)

        clock.advance(by: 12)
        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.isCorrect)
        #expect(payload.speedBonus == 2)
        #expect(payload.solveMs == 12_000)
        #expect(payload.hintsUsed == 0)
    }

    @Test func aCorrectGuessAfterTheWindowClaimsNoBonusButKeepsTheSolveTime() async throws {
        let environment = makeEnvironment(guessing)
        let viewModel = makeViewModel(environment)
        await viewModel.reload()
        let seen = await waitUntil { viewModel.localFirstSeenAt[GameFixture.roundID] != nil }
        #expect(seen)

        clock.advance(by: 31)
        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.speedBonus == 0)
        #expect(payload.solveMs == 31_000)
    }

    /// The guesser watches live while the drawer has the canvas open. The
    /// 30 seconds start at the drawer's first stroke, not when the canvas opened.
    private func watchingLiveUntilFirstStroke(
        _ environment: GamesTestEnvironment
    ) async throws -> DrawAndGuessViewModel {
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = makeViewModel(environment, live: room)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        viewModel.recompute()
        #expect(viewModel.phase == .watchingLive)
        #expect(viewModel.localFirstSeenAt[GameFixture.roundID] == nil)
        #expect(viewModel.speedBonus == .open)

        // The drawer was busy with something else for a minute before drawing.
        clock.advance(by: 60)
        sendPartnerCanvasSnapshot(on: connection)
        viewModel.recompute()
        #expect(viewModel.localFirstSeenAt[GameFixture.roundID] == clock.now)
        #expect(viewModel.speedBonusRemaining() == 30)
        return viewModel
    }

    private var partnerDrawingLive: RemoteDrawAndGuessState {
        GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
    }

    @Test func aLiveGuessWithinThirtySecondsOfTheFirstStrokeClaimsTheBonus() async throws {
        let environment = makeEnvironment(partnerDrawingLive)
        let viewModel = try await watchingLiveUntilFirstStroke(environment)

        clock.advance(by: 20)
        #expect(viewModel.speedBonusRemaining() == 10)
        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.speedBonus == 1)
        #expect(payload.solveMs == 20_000)
    }

    @Test func aLiveGuessMoreThanThirtySecondsAfterTheFirstStrokeClaimsNoBonus() async throws {
        let environment = makeEnvironment(partnerDrawingLive)
        let viewModel = try await watchingLiveUntilFirstStroke(environment)

        clock.advance(by: 31)
        #expect(!viewModel.speedBonusIsAvailable)
        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.speedBonus == 0)
        #expect(payload.solveMs == 31_000)
    }

    @Test func aGuessBeforeThePlayerSawAnythingClaimsTheBonusWithoutASolveTime() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let environment = makeEnvironment(drawingState)
        let viewModel = makeViewModel(environment)
        await viewModel.reload()
        #expect(viewModel.phase == .waitingForDrawing)

        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.speedBonus == 2)
        #expect(payload.solveMs == nil)
    }

    @Test func theClaimIgnoresThePlayStyle() async throws {
        let together = GameFixture.state(
            settings: RemoteGameSettings(
                coupleID: DeveloperScenarioFixture.coupleID,
                playStyle: .together,
                language: .en,
                updatedByUserID: GameFixture.me,
                createdAt: GameFixture.now,
                updatedAt: GameFixture.now
            ),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
        let environment = makeEnvironment(together)
        let viewModel = makeViewModel(environment)
        await viewModel.reload()
        let seen = await waitUntil { viewModel.localFirstSeenAt[GameFixture.roundID] != nil }
        #expect(seen)
        #expect(viewModel.speedBonus == .hidden)

        clock.advance(by: 5)
        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.speedBonus == 2)
        #expect(payload.solveMs == 5_000)
    }

    @Test func aWrongGuessClaimsNothing() async throws {
        let environment = makeEnvironment(guessing)
        let viewModel = makeViewModel(environment)
        await viewModel.reload()

        try type("umbrelle", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(!payload.isCorrect)
        #expect(payload.speedBonus == nil)
        #expect(payload.solveMs == nil)
        #expect(payload.hintsUsed == nil)
    }

    @Test func theQueuedGuessSendsTheClaimToTheServerEvenWhenItWaitedOffline() async throws {
        let payload = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now,
            speedBonus: 2,
            solveMs: 12_000,
            hintsUsed: 1
        )
        let wrong = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "cat",
            isCorrect: false,
            createdAt: GameFixture.now
        )
        let handler = SubmitGameGuessPendingOperationHandler(gateway: env.gateway, cache: env.cache)

        _ = try await handler.send(try snapshot(.submitGameGuess, wrong), context: syncContext(env.pending))
        _ = try await handler.send(try snapshot(.submitGameGuess, payload), context: syncContext(env.pending))

        #expect(env.gateway.guesses == ["cat", "umbrella"])
        #expect(env.gateway.guessClaims == [
            ScriptedGamesGateway.GuessClaim(speedBonus: nil, solveMs: nil, hintsUsed: nil),
            ScriptedGamesGateway.GuessClaim(speedBonus: 2, solveMs: 12_000, hintsUsed: 1),
        ])
    }
}
