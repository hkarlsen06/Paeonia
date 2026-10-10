import Foundation

/// Keeps the last profile Convex returned, keyed by the Clerk account that owns
/// it, so the app can open offline.
protocol AuthSessionCaching: Actor {
    func load(accountID: String) -> AuthSession?
    func save(_ session: AuthSession, accountID: String)
    func clear()
}

/// User ids cross JSON and the Convex client. UUID text is case-insensitive, so
/// identity checks must compare parsed UUID values rather than their transport
/// spelling. The exact fallback keeps local development
/// identities usable without making two different opaque ids equivalent.
nonisolated enum AuthUserIdentity {
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        if let lhsUUID = UUID(uuidString: lhs),
           let rhsUUID = UUID(uuidString: rhs) {
            return lhsUUID == rhsUUID
        }

        return lhs == rhs
    }
}

nonisolated enum AuthSessionFallbackPolicy {
    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Only transport failures may use the last server-verified profile. A
    /// backend authorization, missing-row, or decoding error must fail closed
    /// instead of reviving cached access after the backend rejected the profile.
    static func allowsCachedSession(for error: any Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        return switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            true
        default:
            false
        }
    }
}

actor TransientAuthSessionCache: AuthSessionCaching {
    private var stored: (session: AuthSession, accountID: String)?

    func load(accountID: String) -> AuthSession? {
        guard let stored, stored.accountID == accountID else {
            return nil
        }
        return stored.session
    }

    func save(_ session: AuthSession, accountID: String) {
        stored = (session, accountID)
    }

    func clear() {
        stored = nil
    }
}

actor UserDefaultsAuthSessionCache: AuthSessionCaching {
    static let shared = UserDefaultsAuthSessionCache()

    private struct StoredSession: Codable {
        let accountID: String
        let id: String
        let provider: AuthProvider
        let displayName: String?
        let timeZoneID: String?
        let customProfilePhotoAssetID: UUID?
        let providerProfilePhotoAssetID: UUID?
        let profileStatus: AuthProfileStatus

        init(_ session: AuthSession, accountID: String) {
            self.accountID = accountID
            id = session.id
            provider = session.provider
            displayName = session.displayName
            timeZoneID = session.timeZoneID
            customProfilePhotoAssetID = session.customProfilePhotoAssetID
            providerProfilePhotoAssetID = session.providerProfilePhotoAssetID
            profileStatus = session.profileStatus
        }

        var session: AuthSession {
            AuthSession(
                id: id,
                provider: provider,
                displayName: displayName,
                timeZoneID: timeZoneID,
                profilePhotoAssetID: nil,
                profileStatus: profileStatus,
                customProfilePhotoAssetID: customProfilePhotoAssetID,
                providerProfilePhotoAssetID: providerProfilePhotoAssetID
            )
        }
    }

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "auth.cachedSession.v2"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load(accountID: String) -> AuthSession? {
        guard let data = defaults.data(forKey: key),
              let storedSession = try? JSONDecoder().decode(StoredSession.self, from: data),
              storedSession.accountID == accountID
        else {
            return nil
        }

        return storedSession.session
    }

    func save(_ session: AuthSession, accountID: String) {
        guard let data = try? JSONEncoder().encode(StoredSession(session, accountID: accountID)) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        // The Supabase-era cache holds a user id that no longer exists.
        defaults.removeObject(forKey: "auth.cachedSession.v1")
    }
}
