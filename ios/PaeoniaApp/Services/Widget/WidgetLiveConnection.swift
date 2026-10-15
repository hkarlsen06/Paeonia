import Foundation

/// Where and how to reach the live drawing relay, from `widget:create_widget_live_ticket`.
nonisolated struct WidgetLiveTicket: Decodable, Sendable {
    let url: URL
    let ticket: String
}

/// Keeps one socket open to the live drawing relay while the canvas is on
/// screen. After a drop it waits (1 s doubling to 30 s) and connects again with
/// a fresh ticket, so Convex checks access on every connect. Not final, so the
/// two-phone simulation tests can stand in a fake relay for the socket.
@MainActor
class WidgetLiveConnection {
    typealias TicketProvider = @Sendable (UUID) async throws -> WidgetLiveTicket?

    nonisolated static let defaultTicketProvider: TicketProvider = { coupleID in
        let client = try PaeoniaConvexClientProvider.shared.client()
        return try await client.mutation(
            "widget:create_widget_live_ticket",
            args: ["p_couple_id": coupleID.uuidString]
        )
    }

    private static let pingInterval: Duration = .seconds(25)
    private static let maxBackoff: Duration = .seconds(30)

    var onMessage: ((WidgetLiveMessage) -> Void)?
    /// A game's own message, as the JSON of a `GameLiveEnvelope`. `GameLiveChannel`
    /// decodes it.
    var onGameData: ((Data) -> Void)?
    /// The socket closed. Not called after `stop()`.
    var onDisconnect: (() -> Void)?

    private let coupleID: UUID
    private let ticketProvider: TicketProvider
    private let session: URLSession
    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        coupleID: UUID,
        ticketProvider: @escaping TicketProvider = defaultTicketProvider,
        session: URLSession = .shared
    ) {
        self.coupleID = coupleID
        self.ticketProvider = ticketProvider
        self.session = session
    }

    func start() {
        guard runTask == nil else {
            return
        }
        runTask = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Sends when connected. A message sent while offline is dropped: the next
    /// connect sends the whole drawing again.
    func send(_ message: WidgetLiveMessage) {
        guard let socket,
              let data = try? encoder.encode(message),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }
        socket.send(.string(text)) { _ in }
    }

    /// Sends a game's own message, the JSON of a `GameLiveEnvelope`. Dropped
    /// while offline, like `send(_:)`.
    func send(gameData: Data) {
        guard let socket, let text = String(data: gameData, encoding: .utf8) else {
            return
        }
        socket.send(.string(text)) { _ in }
    }

    private func run() async {
        var backoff: Duration = .seconds(1)
        while !Task.isCancelled {
            let ticket: WidgetLiveTicket?
            do {
                ticket = try await ticketProvider(coupleID)
            } catch {
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, Self.maxBackoff)
                continue
            }
            // No relay is set up on the server. Drawing works as before.
            guard let ticket, !Task.isCancelled else {
                return
            }

            var request = URLRequest(url: ticket.url)
            request.setValue("Bearer \(ticket.ticket)", forHTTPHeaderField: "Authorization")
            let socket = session.webSocketTask(with: request)
            // A full drawing sent to someone who joins can be larger than the
            // 1 MB default. The relay accepts up to 4 MB.
            socket.maximumMessageSize = 4 * 1_048_576
            self.socket = socket
            socket.resume()
            // Proxies close a socket that has been quiet for about 100 seconds.
            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pingInterval)
                    // A failed ping means the connection is gone even if receive has not noticed.
                    // Cancelling makes receive return, so the loop reconnects.
                    socket.sendPing { error in
                        if error != nil { socket.cancel(with: .goingAway, reason: nil) }
                    }
                }
            }

            if await receiveUntilClosed(socket) {
                backoff = .seconds(1)
            }
            pinger.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            guard !Task.isCancelled else {
                return
            }
            self.socket = nil
            onDisconnect?()
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * 2, Self.maxBackoff)
        }
    }

    /// Hands each message to `onMessage` until the socket closes, by either
    /// side or by the network. Returns whether any message arrived.
    private func receiveUntilClosed(_ socket: URLSessionWebSocketTask) async -> Bool {
        var didReceive = false
        while !Task.isCancelled {
            guard let message = try? await socket.receive() else {
                break
            }
            didReceive = true
            guard case let .string(text) = message else {
                continue
            }
            let data = Data(text.utf8)
            if GameLiveEnvelopeTag.isGameMessage(data, decoder: decoder) {
                onGameData?(data)
            } else if let decoded = try? decoder.decode(WidgetLiveMessage.self, from: data) {
                onMessage?(decoded)
            }
        }
        return didReceive
    }
}
