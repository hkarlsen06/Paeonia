import Foundation

/// One call setup message on the relay, sent as `{"call": {...}}` next to the drawing and game
/// messages that share the socket code. `call_id` names the call, so a message for another call
/// is ignored.
nonisolated struct CallSignal: Equatable, Sendable {
    nonisolated enum Message: Equatable, Sendable {
        /// The caller's session description. A later offer restarts the connection. `number`
        /// counts the call's offers.
        case offer(sdp: String, number: Int)
        /// Carries the `number` of the offer it answers, so the caller can drop an answer to an
        /// offer it already replaced.
        case answer(sdp: String, number: Int)
        case candidate(CallIceCandidate)
        /// The sender's camera turned on or off, or iOS paused or resumed it.
        case camera(CallCameraState)
        /// Whether what the sender sends reaches this phone badly (`CallConnectionHealth`).
        case connection(isWeak: Bool)
        /// The sender started or stopped sharing their screen.
        case screen(isOn: Bool)
        /// From the answering phone: its connection dropped, so the caller should offer again.
        case restart
    }

    let callID: UUID
    let message: Message
}

nonisolated struct CallIceCandidate: Equatable, Sendable {
    let sdp: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

/// How a call message travels: `{"call": {"call_id": "…", "type": "offer", "sdp": "…"}}`.
nonisolated struct CallLiveEnvelope: Codable, Sendable {
    let call: CallSignal
}

/// Reads only whether the `call` key is there, so the connection can route a message before
/// anyone decodes it.
nonisolated struct CallLiveEnvelopeTag: Decodable {
    private enum CodingKeys: String, CodingKey {
        case call
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.call) else {
            throw DecodingError.keyNotFound(
                CodingKeys.call,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not a call message")
            )
        }
    }
}

nonisolated extension CallSignal: Codable {
    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case type
        case sdp
        case offerNumber = "offer_number"
        case candidate
        case sdpMid = "sdp_mid"
        case sdpMLineIndex = "sdp_m_line_index"
        case cameraState = "state"
        case isWeak = "weak"
        case isOn = "on"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(UUID.self, forKey: .callID)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "offer":
            message = try .offer(
                sdp: container.decode(String.self, forKey: .sdp),
                number: container.decode(Int.self, forKey: .offerNumber)
            )
        case "answer":
            message = try .answer(
                sdp: container.decode(String.self, forKey: .sdp),
                number: container.decode(Int.self, forKey: .offerNumber)
            )
        case "candidate":
            message = try .candidate(CallIceCandidate(
                sdp: container.decode(String.self, forKey: .candidate),
                sdpMid: container.decodeIfPresent(String.self, forKey: .sdpMid),
                sdpMLineIndex: container.decode(Int32.self, forKey: .sdpMLineIndex)
            ))
        case "camera":
            message = try .camera(container.decode(CallCameraState.self, forKey: .cameraState))
        case "connection":
            message = try .connection(isWeak: container.decode(Bool.self, forKey: .isWeak))
        case "screen":
            message = try .screen(isOn: container.decode(Bool.self, forKey: .isOn))
        case "restart":
            message = .restart
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown call message \(type)"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        switch message {
        case let .offer(sdp, number):
            try container.encode("offer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
            try container.encode(number, forKey: .offerNumber)
        case let .answer(sdp, number):
            try container.encode("answer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
            try container.encode(number, forKey: .offerNumber)
        case let .candidate(candidate):
            try container.encode("candidate", forKey: .type)
            try container.encode(candidate.sdp, forKey: .candidate)
            try container.encodeIfPresent(candidate.sdpMid, forKey: .sdpMid)
            try container.encode(candidate.sdpMLineIndex, forKey: .sdpMLineIndex)
        case let .camera(state):
            try container.encode("camera", forKey: .type)
            try container.encode(state, forKey: .cameraState)
        case let .connection(isWeak):
            try container.encode("connection", forKey: .type)
            try container.encode(isWeak, forKey: .isWeak)
        case let .screen(isOn):
            try container.encode("screen", forKey: .type)
            try container.encode(isOn, forKey: .isOn)
        case .restart:
            try container.encode("restart", forKey: .type)
        }
    }
}

/// Sent as `"off"`, `"on"` or `"paused"`.
nonisolated extension CallCameraState: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "off": self = .off
        case "on": self = .on
        case "paused": self = .paused
        case let other:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown camera state \(other)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .off: try container.encode("off")
        case .on: try container.encode("on")
        case .paused: try container.encode("paused")
        }
    }
}

/// The call's room on the relay. It carries the setup messages and says when the partner's
/// phone is in the room, which is when the caller sends its offer.
@MainActor
final class CallRelay {
    /// The relay reconnects fast during a call, because the call ends after 30 seconds without one.
    private static let maxBackoff: Duration = .seconds(2)

    var onSignal: ((CallSignal.Message) -> Void)?
    /// The partner's phone joined the room, or this phone joined a room the partner was in.
    var onPartnerPresent: (() -> Void)?

    let callID: UUID
    private let connection: WidgetLiveConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var partnerSockets = 0

    init(callID: UUID, backend: CallBackend) {
        self.callID = callID
        // The ticket names the call's room, so the connection's id is the call's.
        connection = WidgetLiveConnection(
            coupleID: callID,
            ticketProvider: { callID in try await backend.liveTicket(callID: callID) },
            maxBackoff: Self.maxBackoff
        )
        connection.onMessage = { [weak self] message in
            self?.receivePresence(message)
        }
        connection.onCallData = { [weak self] data in
            self?.receiveCall(data)
        }
        connection.onDisconnect = { [weak self] in
            self?.partnerSockets = 0
        }
    }

    var isPartnerPresent: Bool {
        partnerSockets > 0
    }

    func start() {
        connection.start()
    }

    func stop() {
        connection.stop()
        partnerSockets = 0
    }

    /// Drops the socket and connects again at once, such as after the phone changed networks.
    func reconnectNow() {
        partnerSockets = 0
        connection.reconnectNow()
    }

    func send(_ message: CallSignal.Message) {
        let envelope = CallLiveEnvelope(call: CallSignal(callID: callID, message: message))
        guard let data = try? encoder.encode(envelope) else {
            return
        }
        connection.send(callData: data)
    }

    private func receivePresence(_ message: WidgetLiveMessage) {
        switch message.type {
        case .welcome:
            partnerSockets = message.peers ?? 0
        case .joined:
            partnerSockets += 1
        case .left:
            partnerSockets = max(0, partnerSockets - 1)
            return
        default:
            return
        }
        if isPartnerPresent {
            onPartnerPresent?()
        }
    }

    private func receiveCall(_ data: Data) {
        guard let envelope = try? decoder.decode(CallLiveEnvelope.self, from: data),
              envelope.call.callID == callID
        else {
            return
        }
        onSignal?(envelope.call.message)
    }
}
