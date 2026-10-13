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

/// The guess carries what the player saw: whether the speed bonus was still on
/// screen and how long they had looked at the drawing, on the phone's clock.
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
        #expect(payload.speedBonus == true)
        #expect(payload.solveMs == 12_000)
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
        #expect(payload.speedBonus == false)
        #expect(payload.solveMs == 31_000)
    }

    @Test func aLiveGuessBeforeDoneClaimsTheBonusHoweverLongTheDrawingTook() async throws {
        let drawingState = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .drawing, turn: GameFixture.me),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.partner)
        )
        let environment = makeEnvironment(drawingState)
        let (room, connection) = makeOfflineLiveRoom()
        let viewModel = makeViewModel(environment, live: room)
        viewModel.configure(participants: GameFixture.participants)
        await viewModel.reload()
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        viewModel.recompute()
        #expect(viewModel.phase == .watchingLive)
        #expect(viewModel.localFirstSeenAt[GameFixture.roundID] != nil)

        clock.advance(by: 50)
        try type("umbrella", into: viewModel)

        let payload = try await queuedGuess(environment)
        #expect(payload.speedBonus == true)
        #expect(payload.solveMs == 50_000)
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
        #expect(payload.speedBonus == true)
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
        #expect(payload.speedBonus == true)
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
    }

    @Test func theQueuedGuessSendsTheClaimToTheServerEvenWhenItWaitedOffline() async throws {
        let payload = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now,
            speedBonus: true,
            solveMs: 12_000
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
            ScriptedGamesGateway.GuessClaim(speedBonus: nil, solveMs: nil),
            ScriptedGamesGateway.GuessClaim(speedBonus: true, solveMs: 12_000),
        ])
    }
}
