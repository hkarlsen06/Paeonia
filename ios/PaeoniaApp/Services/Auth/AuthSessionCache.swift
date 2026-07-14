import Foundation

protocol AuthSessionCaching: Actor {
    func load(userID: String) -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

nonisolated enum AuthSessionFallbackPolicy {
    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Only transport failures may use the last server-verified profile. A
    /// PostgREST authorization, missing-row, or decoding error must fail closed
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
    private var session: AuthSession?

    func load(userID: String) -> AuthSession? {
        guard session?.id == userID else {
            return nil
        }
        return session
    }

    func save(_ session: AuthSession) {
        self.session = session
    }

    func clear() {
        session = nil
    }
}

actor UserDefaultsAuthSessionCache: AuthSessionCaching {
    static let shared = UserDefaultsAuthSessionCache()

    private struct StoredSession: Codable {
        let id: String
        let provider: String
        let displayName: String?
        let timeZoneID: String?
        let customProfilePhotoAssetID: UUID?
        let providerProfilePhotoAssetID: UUID?
        let profileStatus: String

        init(_ session: AuthSession) {
            id = session.id
            provider = switch session.provider {
            case .apple: "apple"
            case .google: "google"
            case .development: "development"
            case .unknown: "unknown"
            }
            displayName = session.displayName
            timeZoneID = session.timeZoneID
            customProfilePhotoAssetID = session.customProfilePhotoAssetID
            providerProfilePhotoAssetID = session.providerProfilePhotoAssetID
            profileStatus = switch session.profileStatus {
            case .needsOnboarding: "needsOnboarding"
            case .complete: "complete"
            }
        }

        var session: AuthSession? {
            guard let provider = AuthProvider(storedValue: provider),
                  let profileStatus = AuthProfileStatus(storedValue: profileStatus)
            else {
                return nil
            }

            return AuthSession(
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
        key: String = "auth.cachedSession.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load(userID: String) -> AuthSession? {
        guard let data = defaults.data(forKey: key),
              let storedSession = try? JSONDecoder().decode(StoredSession.self, from: data),
              storedSession.id == userID
        else {
            return nil
        }

        return storedSession.session
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(StoredSession(session)) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

private extension AuthProvider {
    nonisolated init?(storedValue: String) {
        switch storedValue {
        case "apple": self = .apple
        case "google": self = .google
        case "development": self = .development
        case "unknown": self = .unknown
        default: return nil
        }
    }
}

private extension AuthProfileStatus {
    nonisolated init?(storedValue: String) {
        switch storedValue {
        case "needsOnboarding": self = .needsOnboarding
        case "complete": self = .complete
        default: return nil
        }
    }
}
