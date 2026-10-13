import Foundation

/// A game's own message type on its relay room. Each game declares one type and
/// names itself with `game`. The live drawing messages (`WidgetLiveMessage`)
/// share the socket, and the relay forwards both without reading them.
///
/// To give a new game live messages: declare its message type, add its relay
/// channel to `ALLOWED_CHANNELS` in `relay/src/ticket.ts`, and open a
/// `GameLiveChannel` on the game's connection.
nonisolated protocol GameLiveMessage: Codable, Sendable {
    /// Names the game on the wire, such as `draw_and_guess`.
    static var game: String { get }
}

/// How a game message travels: `{"game": "draw_and_guess", "message": {...}}`.
/// The `game` key tells it apart from a live drawing message, which has none.
nonisolated struct GameLiveEnvelope<Message: GameLiveMessage>: Codable {
    let game: String
    let message: Message
}

/// Reads only the `game` key, so the connection can route a message before
/// anyone decodes it.
nonisolated struct GameLiveEnvelopeTag: Decodable {
    let game: String

    static func isGameMessage(_ data: Data, decoder: JSONDecoder) -> Bool {
        (try? decoder.decode(Self.self, from: data)) != nil
    }
}

/// Sends and receives one game's messages on a live connection. A connection
/// carries one game, because every game has its own relay room. Messages sent
/// while offline are dropped, so send whole state that the partner can take as
/// it is, and send it again when the partner arrives.
@MainActor
final class GameLiveChannel<Message: GameLiveMessage> {
    var onMessage: ((Message) -> Void)?

    private let connection: WidgetLiveConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(connection: WidgetLiveConnection) {
        self.connection = connection
        connection.onGameData = { [weak self] data in
            self?.receive(data)
        }
    }

    func send(_ message: Message) {
        guard let data = try? encoder.encode(GameLiveEnvelope(game: Message.game, message: message)) else {
            return
        }
        connection.send(gameData: data)
    }

    private func receive(_ data: Data) {
        guard let envelope = try? decoder.decode(GameLiveEnvelope<Message>.self, from: data),
              envelope.game == Message.game
        else {
            return
        }
        onMessage?(envelope.message)
    }
}
