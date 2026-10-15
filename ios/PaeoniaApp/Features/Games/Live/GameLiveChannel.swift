import Foundation

/// A game's own message type on its relay room. Each game declares one type and
/// names itself with `game`. The live drawing messages (`WidgetLiveMessage`)
/// share the socket, and the relay forwards both without reading them.
///
/// To give a new game live messages: declare its message type and open a
/// `GameLiveChannel` on a connection made with `GameLiveTicket.provider(for:)`.
/// Every `GameKind` has its relay channel on the allowlist already
/// (`ALLOWED_CHANNELS` in `relay/src/ticket.ts`).
nonisolated protocol GameLiveMessage: Codable, Sendable {
    /// Names the game on the wire, such as `draw_and_guess`.
    static var game: String { get }
}

/// The relay ticket for one game's room.
nonisolated enum GameLiveTicket {
    /// Asks Convex for a 60-second relay ticket on every connect, so access is
    /// checked again after each drop and after the relay's 10-minute session
    /// limit. The ticket puts the socket in the room `<couple>:<kind.relayChannel>`.
    /// A nil ticket means the relay is not set up, and the game plays without live
    /// messages.
    nonisolated static func provider(for kind: GameKind) -> WidgetLiveConnection.TicketProvider {
        return { _ in
            let client = try PaeoniaConvexClientProvider.shared.client()
            return try await client.mutation(
                "games:create_game_live_ticket",
                args: ["p_kind": kind.rawValue]
            )
        }
    }
}

/// A game's room on the relay, for presence and the game's own messages. It is a
/// `WidgetLiveDrawing` so the game shares the socket code of the widget canvas,
/// but each game has a room of its own (`<couple>:<kind.relayChannel>`), so a
/// game never shares the four-socket cap with Home and the canvas. Only Draw & Guess
/// attaches a canvas to it. The drawer joins with the `drawing` role and the
/// guesser with `watching`. The other games join with `present`.
@MainActor
enum GameLiveRoom {
    static func make(
        _ kind: GameKind,
        coupleID: UUID,
        role: WidgetLivePresence.Role = .present
    ) -> WidgetLiveDrawing {
        WidgetLiveDrawing(
            connection: WidgetLiveConnection(
                coupleID: coupleID,
                ticketProvider: GameLiveTicket.provider(for: kind)
            ),
            role: role,
            presence: WidgetLivePresence(countsLatestHelloOnly: true)
        )
    }
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
/// carries one game, because every game has its own relay room, which the
/// connection's ticket names (see `GameLiveTicket`). Messages sent while offline
/// are dropped, so send whole state that the partner can take as it is, and send
/// it again when the partner arrives.
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
