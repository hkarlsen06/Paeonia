import Foundation
import Security

/// The server half of the game Live Activity tokens (`backend/convex/liveActivities.ts`).
nonisolated protocol LiveActivityTokenServer: Sendable {
    func register(_ registration: LiveActivityTokenRegistration) async throws -> LiveActivityRegistrationResult
    /// Sent without a sign-in, because the session may already be gone.
    func endInstall(_ installID: String) async throws
    /// The phone with install `installID` ended the activity with server id `activityID` on its own.
    func endActivity(_ activityID: String, installID: String) async throws
}

/// The server's answer to a registration.
nonisolated enum LiveActivityRegistrationResult: String, Decodable, Sendable {
    /// A push-to-start token is saved.
    case saved
    /// The activity runs, and its updates go to the token.
    case playing
    /// The activity no longer runs, or is not this account's, so nothing will reach it.
    case ended
    /// The install id holds another account's tokens. This phone needs a new one.
    case installTaken = "install_taken"
}

nonisolated struct LiveActivityTokenRegistration: Encodable, Equatable, Sendable {
    enum Kind: String, Encodable, Sendable {
        /// The token that lets the server start an activity on this phone.
        case start
        /// The token of one running activity, for its updates and its end.
        case update
    }

    let installID: String
    let kind: Kind
    let token: String
    let apnsEnvironment: String
    let activityID: String?
    let locale: String

    enum CodingKeys: String, CodingKey {
        case installID = "p_install_id"
        case kind = "p_kind"
        case token = "p_token"
        case apnsEnvironment = "p_apns_environment"
        case activityID = "p_activity_id"
        case locale = "p_locale"
    }
}

/// This phone's install for the game Live Activity: a new id for each sign-in, kept with the
/// account it belongs to, and the installs whose sign-in ended and whose end the server has
/// not confirmed yet.
nonisolated struct LiveActivityInstallState: Codable, Equatable, Sendable {
    struct PendingEnd: Codable, Equatable, Sendable {
        let installID: String
        let endedAt: Date
    }

    var installID: String?
    var accountID: String?
    var pendingEnds: [PendingEnd] = []
}

nonisolated protocol LiveActivityInstallStore: Sendable {
    /// Throws when the state cannot be read now, such as before the first unlock after a restart.
    func load() throws -> LiveActivityInstallState
    func save(_ state: LiveActivityInstallState) throws
}

/// Keeps the install ids of one phone and tells the server when a sign-in ends. An end goes out
/// at once and again `settleInterval` later, so a registration that was on its way during the
/// sign-out cannot leave a token behind. One phone never holds two start tokens anyway, because
/// the server keeps one row per token.
final class LiveActivityInstallRegistry {
    static let settleInterval: TimeInterval = 120

    private let store: any LiveActivityInstallStore
    private let server: any LiveActivityTokenServer
    private let now: () -> Date

    init(
        store: any LiveActivityInstallStore,
        server: any LiveActivityTokenServer,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.server = server
        self.now = now
    }

    /// The account the current install belongs to. Nil when nobody is signed in on it.
    var accountID: String? {
        get throws { try store.load().accountID }
    }

    /// The sign-in ended. Its install waits for the server's end, and the next registration makes a new one.
    func endInstall() throws {
        var state = try store.load()
        guard let installID = state.installID else {
            return
        }
        state.pendingEnds.append(.init(installID: installID, endedAt: now()))
        state.installID = nil
        state.accountID = nil
        try store.save(state)
    }

    /// Tells the server about each ended install. An end stays pending until a send that started
    /// `settleInterval` after the sign-in ended went through. Returns when the next send is due,
    /// or nil when no end waits. Throws at the first failure, which stays pending.
    func sendEnds() async throws -> Date? {
        let startedAt = now()
        for end in try store.load().pendingEnds {
            try await server.endInstall(end.installID)
            if startedAt >= end.endedAt.addingTimeInterval(Self.settleInterval) {
                var state = try store.load()
                state.pendingEnds.removeAll { $0 == end }
                try store.save(state)
            }
        }
        return try store.load().pendingEnds.map { $0.endedAt.addingTimeInterval(Self.settleInterval) }.min()
    }

    /// Registers a token for `accountID`. An install of another account on this phone ends first.
    func register(
        _ kind: LiveActivityTokenRegistration.Kind,
        token: String,
        activityID: String?,
        for accountID: String
    ) async throws -> LiveActivityRegistrationResult {
        let result = try await server.register(registration(kind, token: token, activityID: activityID, for: accountID))
        guard result == .installTaken else {
            return result
        }
        // The id belongs to another account on the server, so it is not this phone's to end.
        var state = try store.load()
        state.installID = nil
        state.accountID = nil
        try store.save(state)
        return try await server.register(registration(kind, token: token, activityID: activityID, for: accountID))
    }

    /// This phone ended the activity on its own. The server stops sending to it here, and the
    /// account's other phones keep it.
    func endActivity(_ activityID: String, for accountID: String) async throws {
        try await server.endActivity(activityID, installID: installID(for: accountID))
    }

    private func registration(
        _ kind: LiveActivityTokenRegistration.Kind,
        token: String,
        activityID: String?,
        for accountID: String
    ) throws -> LiveActivityTokenRegistration {
        LiveActivityTokenRegistration(
            installID: try installID(for: accountID),
            kind: kind,
            token: token,
            apnsEnvironment: ConvexPushRegistrationService.apnsEnvironment,
            activityID: activityID,
            locale: Locale.current.identifier
        )
    }

    private func installID(for accountID: String) throws -> String {
        if try self.accountID != accountID {
            try endInstall()
        }
        var state = try store.load()
        if let installID = state.installID {
            return installID
        }
        let installID = UUID().uuidString
        state.installID = installID
        state.accountID = accountID
        try store.save(state)
        return installID
    }
}

/// The install state in a keychain item that stays on this phone. A backup restored to another
/// phone or a device transfer does not carry it, so two phones never share an install id.
nonisolated struct KeychainLiveActivityInstallStore: LiveActivityInstallStore {
    struct Unreadable: Error {
        let status: OSStatus
    }

    var service = "no.paeonia.live-activity-install"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "install",
        ]
    }

    func load() throws -> LiveActivityInstallState {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound {
            return LiveActivityInstallState()
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Unreadable(status: status)
        }
        return try JSONDecoder().decode(LiveActivityInstallState.self, from: data)
    }

    func save(_ state: LiveActivityInstallState) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(state),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw Unreadable(status: status)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated struct ConvexLiveActivityTokenServer: LiveActivityTokenServer {
    let client: PaeoniaConvexClient
    let signedOutClient: PaeoniaConvexClient

    static func makeDefault() -> ConvexLiveActivityTokenServer? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client(),
              let deploymentURL = try? PaeoniaConvexClientProvider.deploymentURL(in: .main)
        else {
            return nil
        }
        return ConvexLiveActivityTokenServer(
            client: client,
            signedOutClient: PaeoniaConvexClient(deploymentURL: deploymentURL) { nil }
        )
    }

    func register(_ registration: LiveActivityTokenRegistration) async throws -> LiveActivityRegistrationResult {
        try await client.mutation("liveActivities:register_live_activity_token", args: registration)
    }

    func endInstall(_ installID: String) async throws {
        try await signedOutClient.mutation(
            "liveActivities:end_live_activity_install",
            args: ["p_install_id": installID]
        )
    }

    func endActivity(_ activityID: String, installID: String) async throws {
        try await client.mutation(
            "liveActivities:end_game_live_activity",
            args: ["p_activity_id": activityID, "p_install_id": installID]
        )
    }
}
