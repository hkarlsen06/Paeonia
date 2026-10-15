import Foundation
@testable import PaeoniaApp

/// The live drawing relay (`relay/src/index.ts`) for one couple room. It sends
/// `welcome` to a new socket and `joined` and `left` to the partner's sockets,
/// forwards each app message to the partner's sockets only, holds at most four
/// sockets, and closes a socket after its 10-minute session. A socket whose
/// phone lost the network stays in the room, silent, until the driver reaps it,
/// as a real socket lingers until the relay notices it is gone.
@MainActor
final class SimRelay {
    final class Socket {
        let id: String
        let user: UUID
        let openedAt: Date
        /// Nil once the phone lost this socket. The relay may not know yet.
        weak var connection: SimRelaySocket?
        var hasLeft = false

        init(id: String, user: UUID, openedAt: Date, connection: SimRelaySocket) {
            self.id = id
            self.user = user
            self.openedAt = openedAt
            self.connection = connection
        }
    }

    private enum Delivery {
        case message(SimRelaySocket, socketID: String, WidgetLiveMessage)
        case gameData(SimRelaySocket, socketID: String, Data)
        case disconnect(SimRelaySocket)
    }

    static let sessionSeconds: TimeInterval = 10 * 60
    static let maxSockets = 4

    private let clock: SimClock
    private let log: SimLog
    private(set) var sockets: [Socket] = []
    private var queue: [Delivery] = []
    private var pumpTask: Task<Void, Never>?
    private var nextID = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(clock: SimClock, log: SimLog) {
        self.clock = clock
        self.log = log
    }

    var isIdle: Bool {
        queue.isEmpty && pumpTask == nil
    }

    private var open: [Socket] {
        sockets.filter { !$0.hasLeft }
    }

    func connect(_ connection: SimRelaySocket, user: UUID) -> Socket? {
        expireSessions()
        guard open.count < Self.maxSockets else {
            log.add("relay full for \(connection.phoneName)")
            return nil
        }
        nextID += 1
        let socket = Socket(id: "s\(nextID)", user: user, openedAt: clock.now, connection: connection)
        let peers = open.filter { $0.user != user }.count
        sockets.append(socket)
        log.add("relay \(connection.phoneName) connect \(socket.id) peers=\(peers)")
        let welcome = WidgetLiveMessage(type: .welcome, id: socket.id, peers: peers)
        enqueue(.message(connection, socketID: socket.id, welcome))
        broadcast(from: socket, WidgetLiveMessage(type: .joined, id: socket.id))
        return socket
    }

    /// The app closed the socket, so the relay hears the close at once.
    func close(_ socket: Socket) {
        leave(socket)
    }

    /// The phone lost the socket without a close. The relay keeps it until `reapGhosts`.
    func lose(_ socket: Socket) {
        socket.connection = nil
    }

    /// The relay notices the sockets whose phone is gone.
    func reapGhosts() {
        for socket in open where socket.connection == nil {
            log.add("relay reap \(socket.id)")
            leave(socket)
        }
    }

    func forward(from socket: Socket, _ message: WidgetLiveMessage) {
        guard !socket.hasLeft else { return }
        // Through JSON, as the real socket carries it.
        guard let data = try? encoder.encode(message),
              let decoded = try? decoder.decode(WidgetLiveMessage.self, from: data)
        else { return }
        broadcast(from: socket, decoded)
        if isExpired(socket) {
            expire(socket)
        }
    }

    /// A game's own message, forwarded unread as the relay does.
    func forward(from socket: Socket, gameData: Data) {
        guard !socket.hasLeft else { return }
        broadcast(from: socket) { .gameData($0, socketID: $1, gameData) }
        if isExpired(socket) {
            expire(socket)
        }
    }

    /// Closes every socket past its session, as the room's alarm does.
    func expireSessions() {
        for socket in open where isExpired(socket) {
            expire(socket)
        }
    }

    private func isExpired(_ socket: Socket) -> Bool {
        clock.now.timeIntervalSince(socket.openedAt) > Self.sessionSeconds
    }

    private func expire(_ socket: Socket) {
        log.add("relay expire \(socket.id)")
        leave(socket)
        if let connection = socket.connection {
            socket.connection = nil
            enqueue(.disconnect(connection))
        }
    }

    private func leave(_ socket: Socket) {
        guard !socket.hasLeft else { return }
        socket.hasLeft = true
        broadcast(from: socket, WidgetLiveMessage(type: .left, id: socket.id))
        sockets.removeAll { $0.hasLeft }
    }

    private func broadcast(from sender: Socket, _ message: WidgetLiveMessage) {
        broadcast(from: sender) { .message($0, socketID: $1, message) }
    }

    private func broadcast(from sender: Socket, _ delivery: (SimRelaySocket, String) -> Delivery) {
        for peer in open where peer.user != sender.user {
            if isExpired(peer) {
                expire(peer)
            } else if let connection = peer.connection {
                enqueue(delivery(connection, peer.id))
            }
        }
    }

    private func enqueue(_ delivery: Delivery) {
        queue.append(delivery)
        guard pumpTask == nil else { return }
        pumpTask = Task { @MainActor [weak self] in
            await self?.pump()
        }
    }

    private func pump() async {
        while !queue.isEmpty {
            let delivery = queue.removeFirst()
            switch delivery {
            case let .message(connection, socketID, message):
                // A socket the phone has since lost hears nothing.
                if connection.socketID == socketID {
                    connection.onMessage?(message)
                }
            case let .gameData(connection, socketID, data):
                if connection.socketID == socketID {
                    connection.onGameData?(data)
                }
            case let .disconnect(connection):
                connection.relayDidDisconnect()
            }
            await Task.yield()
        }
        pumpTask = nil
    }
}

/// The game's live connection, on the fake relay instead of a web socket.
@MainActor
final class SimRelaySocket: WidgetLiveConnection {
    let phoneName: String
    private let relay: SimRelay
    private let user: UUID
    private let isOnline: () -> Bool
    /// `games:create_game_live_ticket`, a request on the phone's network before every connect.
    private let fetchTicket: () async throws -> Void
    private var socket: SimRelay.Socket?
    private var wantsConnection = false
    private var isConnecting = false
    /// Told about everything this phone sends, for tests of what may leave the phone.
    var onSendMessage: ((WidgetLiveMessage) -> Void)?
    var onSendGameData: ((Data) -> Void)?

    init(
        relay: SimRelay,
        user: UUID,
        phoneName: String,
        isOnline: @escaping () -> Bool,
        fetchTicket: @escaping () async throws -> Void
    ) {
        self.relay = relay
        self.user = user
        self.phoneName = phoneName
        self.isOnline = isOnline
        self.fetchTicket = fetchTicket
        super.init(coupleID: UUID(), ticketProvider: { _ in nil })
    }

    var socketID: String? {
        socket?.id
    }

    var isConnected: Bool {
        socket != nil
    }

    override func start() {
        wantsConnection = true
        reconnectIfNeeded()
    }

    override func stop() {
        wantsConnection = false
        if let socket {
            relay.close(socket)
        }
        socket = nil
    }

    override func send(_ message: WidgetLiveMessage) {
        onSendMessage?(message)
        guard let socket else { return }
        relay.forward(from: socket, message)
    }

    override func send(gameData: Data) {
        onSendGameData?(gameData)
        guard let socket else { return }
        relay.forward(from: socket, gameData: gameData)
    }

    /// The real connection tries again after a drop. The driver calls this as its backoff.
    func reconnectIfNeeded() {
        guard wantsConnection, socket == nil, !isConnecting, isOnline() else { return }
        isConnecting = true
        Task { [weak self] in
            guard let self else { return }
            defer { isConnecting = false }
            do {
                try await fetchTicket()
                // The socket handshake takes a moment after the ticket.
                try await Task.sleep(for: .milliseconds(3))
            } catch {
                return
            }
            guard wantsConnection, socket == nil, isOnline() else { return }
            socket = relay.connect(self, user: user)
        }
    }

    var isConnectingNow: Bool {
        isConnecting
    }

    /// The phone lost the network or the socket died without a close.
    func dropSilently() {
        guard let socket else { return }
        relay.lose(socket)
        self.socket = nil
        onDisconnect?()
    }

    /// The relay closed the socket at the end of its session.
    func relayDidDisconnect() {
        guard socket != nil else { return }
        socket = nil
        onDisconnect?()
    }
}
