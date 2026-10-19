import Foundation
import QuartzCore
import Testing
@testable import PaeoniaApp

/// A live connection that keeps the game messages sent on it instead of opening a socket.
@MainActor
final class GameDataRecordingConnection: WidgetLiveConnection {
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

    var sentGuessScreens: [DrawAndGuessLiveMessage] {
        sentGameData.compactMap {
            try? JSONDecoder().decode(GameLiveEnvelope<DrawAndGuessLiveMessage>.self, from: $0).message
        }
    }
}

/// The guesser's screen sent over the live room, and the drawer's result screen
/// that shows it.
@MainActor
struct DrawAndGuessLiveGuessTests {
    private typealias Setup = (viewModel: DrawAndGuessViewModel, connection: GameDataRecordingConnection)

    private func envelope(_ message: DrawAndGuessLiveMessage, game: String = DrawAndGuessLiveMessage.game) -> Data {
        (try? JSONEncoder().encode(GameLiveEnvelope(game: game, message: message))) ?? Data()
    }

    private func message(
        round: UUID = GameFixture.roundID,
        letters: [String?] = ["U", nil, nil, nil, nil, nil, nil, nil],
        isWrong: Bool = false,
        replay: DrawAndGuessLiveMessage.Replay? = nil
    ) -> DrawAndGuessLiveMessage {
        DrawAndGuessLiveMessage(round: round, letters: letters, isWrong: isWrong, replay: replay)
    }

    // MARK: Channel

    @Test func aGameMessageTravelsInItsEnvelopeToTheSameGameOnly() throws {
        let sender = GameDataRecordingConnection()
        GameLiveChannel<DrawAndGuessLiveMessage>(connection: sender).send(message())
        let data = try #require(sender.sentGameData.first)
        #expect(GameLiveEnvelopeTag.isGameMessage(data, decoder: JSONDecoder()))

        let receiver = GameDataRecordingConnection()
        let channel = GameLiveChannel<DrawAndGuessLiveMessage>(connection: receiver)
        var received: [DrawAndGuessLiveMessage] = []
        channel.onMessage = { received.append($0) }
        receiver.onGameData?(data)
        receiver.onGameData?(envelope(message(), game: "another_game"))

        #expect(received == [message()])
    }

    @Test func aDrawingMessageIsNotAGameMessage() throws {
        let data = try JSONEncoder().encode(WidgetLiveMessage(type: .hello, from: "me", role: "drawing"))
        #expect(!GameLiveEnvelopeTag.isGameMessage(data, decoder: JSONDecoder()))
    }

    // MARK: Guesser

    private func guessing() async -> Setup {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true)
        )
        let connection = GameDataRecordingConnection()
        let viewModel = GamesTestEnvironment(state: state)
            .viewModel(live: WidgetLiveDrawing(connection: connection, role: .watching))
        await viewModel.reload()
        _ = await waitUntil { viewModel.isReplayReady }
        return (viewModel, connection)
    }

    @Test func placingATileSendsTheLettersAndTheReplay() async throws {
        let (viewModel, connection) = await guessing()
        #expect(viewModel.phase == .guessing)
        let tile = try #require(viewModel.tiles.first)

        viewModel.placeTile(tile)

        let sent = try #require(connection.sentGuessScreens.last)
        #expect(sent.round == GameFixture.roundID)
        #expect(sent.letters.first == String(tile.letter))
        #expect(sent.letters.dropFirst().allSatisfy { $0 == nil })
        #expect(sent.replay?.rate == 1)

        // Nothing changed, so nothing goes again.
        let count = connection.sentGameData.count
        viewModel.recompute()
        #expect(connection.sentGameData.count == count)
    }

    // MARK: Drawer

    private func waitingForGuess() async -> Setup {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        )
        let connection = GameDataRecordingConnection()
        let viewModel = GamesTestEnvironment(state: state)
            .viewModel(live: WidgetLiveDrawing(connection: connection, role: .drawing))
        await viewModel.reload()
        _ = await waitUntil { viewModel.finalDrawing != nil }
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "watching"))
        viewModel.recompute()
        return (viewModel, connection)
    }

    @Test func theDrawerSeesThePartnersLettersAndReplay() async throws {
        let (viewModel, connection) = await waitingForGuess()
        #expect(viewModel.phase == .waitingForGuess)

        connection.onGameData?(envelope(message(replay: .init(time: 0.5, rate: 1))))

        let guess = try #require(viewModel.partnerGuess)
        #expect(guess.slots.slots.first?.tile?.letter == "U")
        #expect(guess.slots.slots.dropFirst().allSatisfy { $0.tile == nil })
        let clock = try #require(guess.replayClock)
        #expect(clock.replayTime(at: CACurrentMediaTime()) >= 0.5)
    }

    @Test func aScreenThatArrivesBeforeTheRoundLoadsShowsOnceItDoes() async {
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true)
        )
        let connection = GameDataRecordingConnection()
        let viewModel = GamesTestEnvironment(state: state)
            .viewModel(live: WidgetLiveDrawing(connection: connection, role: .drawing))
        connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
        connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "watching"))
        connection.onGameData?(envelope(message()))
        #expect(viewModel.partnerGuess == nil)

        await viewModel.reload()

        #expect(viewModel.partnerGuess?.slots.slots.first?.tile?.letter == "U")
    }

    @Test func aScreenForAnotherRoundIsIgnored() async {
        let (viewModel, connection) = await waitingForGuess()

        connection.onGameData?(envelope(message(round: GameFixture.nextRoundID)))

        #expect(viewModel.partnerGuess == nil)
    }
}
