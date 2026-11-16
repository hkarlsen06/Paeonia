import Foundation

/// The couple's live call, from `calls:get_live_call`. The server keeps a row only while the call
/// rings or runs.
nonisolated struct LiveCall: Decodable, Equatable, Sendable {
    enum State: String, Decodable, Sendable {
        case ringing
        case active
    }

    let callID: UUID
    let callerUserID: UUID
    let calleeUserID: UUID
    let state: State
    /// The device that answered (`p_device_id`), once someone has.
    let answeredDeviceID: UUID?
    let ringExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case callerUserID = "caller_user_id"
        case calleeUserID = "callee_user_id"
        case state
        case answeredDeviceID = "answered_device_id"
        case ringExpiresAt = "ring_expires_at"
    }
}

nonisolated struct StartedCall: Decodable, Sendable {
    let callID: UUID
    /// The partner's call was ringing, so the server answered it instead of starting a new one.
    let answeredIncoming: Bool

    enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case answeredIncoming = "answered_incoming"
    }
}

/// The STUN and TURN servers for one call, from `calls:get_call_ice_servers`.
nonisolated struct CallIceServers: Decodable, Sendable {
    nonisolated struct Server: Decodable, Sendable {
        let urls: [String]
        let username: String?
        let credential: String?

        enum CodingKeys: String, CodingKey {
            case urls
            case username
            case credential
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // WebRTC's own format allows one URL or a list.
            if let single = try? container.decode(String.self, forKey: .urls) {
                urls = [single]
            } else {
                urls = try container.decode([String].self, forKey: .urls)
            }
            username = try container.decodeIfPresent(String.self, forKey: .username)
            credential = try container.decodeIfPresent(String.self, forKey: .credential)
        }
    }

    let iceServers: [Server]
    /// Media may only go through TURN, so the partner never sees this phone's address.
    let relayOnly: Bool

    enum CodingKeys: String, CodingKey {
        case iceServers = "ice_servers"
        case relayOnly = "relay_only"
    }
}

/// The server functions a call uses (`backend/convex/calls.ts`).
nonisolated struct CallBackend: Sendable {
    static let busyCode = "P0001"
    static let notRingingCode = "P0002"

    private func client() throws -> PaeoniaConvexClient {
        try PaeoniaConvexClientProvider.shared.client()
    }

    func startCall(callID: UUID, deviceID: UUID) async throws -> StartedCall {
        try await client().mutation(
            "calls:start_call",
            args: ["p_call_id": callID.uuidString, "p_device_id": deviceID.uuidString]
        )
    }

    func answerCall(callID: UUID, deviceID: UUID) async throws {
        try await client().mutation(
            "calls:answer_call",
            args: ["p_call_id": callID.uuidString, "p_device_id": deviceID.uuidString]
        )
    }

    func declineCall(callID: UUID) async throws {
        try await client().mutation("calls:decline_call", args: ["p_call_id": callID.uuidString])
    }

    func endCall(callID: UUID) async throws {
        try await client().mutation("calls:end_call", args: ["p_call_id": callID.uuidString])
    }

    func heartbeat(callID: UUID) async throws {
        try await client().mutation("calls:call_heartbeat", args: ["p_call_id": callID.uuidString])
    }

    /// `calls:get_live_call` read once, over a request that opens on the phone's current network.
    func liveCall() async throws -> LiveCall? {
        try await client().query("calls:get_live_call")
    }

    func partnerTimeZoneID() async throws -> String? {
        let context: CallContext = try await client().query("calls:get_call_context")
        return context.partnerTimeZoneID
    }

    func liveTicket(callID: UUID) async throws -> WidgetLiveTicket? {
        try await client().mutation(
            "calls:create_call_live_ticket",
            args: ["p_call_id": callID.uuidString]
        )
    }

    func reportQuality(callID: UUID, report: CallQualityReport) async throws {
        try await client().mutation(
            "calls:report_call_quality",
            args: QualityArgs(callID: callID.uuidString, report: report)
        )
    }

    func iceServers(callID: UUID) async throws -> CallIceServers {
        try await client().action(
            "calls:get_call_ice_servers",
            args: ["p_call_id": callID.uuidString]
        )
    }

    /// Every result of `calls:get_live_call`, on the live connection the feeds share.
    @MainActor
    func liveCalls() -> AsyncStream<LiveResult<LiveCall?>> {
        LiveQueryService(transport: ConvexLiveTransport(connection: .shared))
            .subscribe("calls:get_live_call", as: LiveCall?.self)
    }

    private nonisolated struct QualityArgs: Encodable {
        let callID: String
        let report: CallQualityReport

        enum CodingKeys: String, CodingKey {
            case callID = "p_call_id"
            case report = "p_report"
        }
    }

    private nonisolated struct CallContext: Decodable {
        let partnerTimeZoneID: String?

        enum CodingKeys: String, CodingKey {
            case partnerTimeZoneID = "partner_time_zone_id"
        }
    }
}

nonisolated extension CallBackend {
    /// The server answered with an error, rather than the request failing on the way. With `code`,
    /// only that error.
    static func isServerError(_ error: any Error, code: String? = nil) -> Bool {
        guard case let .server(errorCode, _)? = error as? PaeoniaConvexError else {
            return false
        }
        return code == nil || errorCode == code
    }
}

nonisolated extension CallFailure {
    /// What a failed server call means for the call, per `PaeoniaFailure`.
    init(_ error: any Error) {
        self = PaeoniaFailure(error) == .offline ? .offline : .other
    }
}

/// A random id for this install of the app, sent as `p_device_id` so the server records which
/// device answered.
nonisolated enum CallDeviceID {
    private static let key = "paeonia.calls.deviceID"

    static let current: UUID = {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }()
}
