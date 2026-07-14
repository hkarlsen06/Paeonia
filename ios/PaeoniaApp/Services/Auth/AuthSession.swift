import Foundation

nonisolated struct AuthSession: Equatable, Identifiable, Sendable {
    let id: String
    let provider: AuthProvider
    let displayName: String?
    let timeZoneID: String?
    /// Paeonia-uploaded override. Removing it reveals the private provider
    /// fallback instead of leaving a Google user without an avatar.
    let customProfilePhotoAssetID: UUID?
    /// Private media imported from OAuth. The provider URL is never persisted.
    let providerProfilePhotoAssetID: UUID?
    let profileStatus: AuthProfileStatus

    var profilePhotoAssetID: UUID? {
        customProfilePhotoAssetID ?? providerProfilePhotoAssetID
    }

    nonisolated init(
        id: String,
        provider: AuthProvider,
        displayName: String?,
        timeZoneID: String?,
        profilePhotoAssetID: UUID?,
        profileStatus: AuthProfileStatus,
        customProfilePhotoAssetID: UUID? = nil,
        providerProfilePhotoAssetID: UUID? = nil
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.timeZoneID = timeZoneID
        self.customProfilePhotoAssetID = customProfilePhotoAssetID ?? profilePhotoAssetID
        self.providerProfilePhotoAssetID = providerProfilePhotoAssetID
        self.profileStatus = profileStatus
    }

    nonisolated func completingOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoAssetID: UUID? = nil
    ) -> AuthSession {
        AuthSession(
            id: id,
            provider: provider,
            displayName: displayName,
            timeZoneID: timeZoneID,
            profilePhotoAssetID: profilePhotoAssetID ?? customProfilePhotoAssetID,
            profileStatus: .complete,
            customProfilePhotoAssetID: profilePhotoAssetID ?? customProfilePhotoAssetID,
            providerProfilePhotoAssetID: providerProfilePhotoAssetID
        )
    }
}

nonisolated enum AuthProvider: String, Codable, Equatable, Sendable {
    case apple
    case google
    case development
    case unknown
}

nonisolated enum AuthProfileStatus: String, Codable, Equatable, Sendable {
    case needsOnboarding
    case complete
}

nonisolated struct AppleSignInCredential: Equatable, Sendable {
    let idToken: String
    let nonce: String
    let fullName: String?
    /// Apple's short-lived authorization code. Sign-in itself only needs the ID
    /// token, but account deletion can exchange this code server-side and revoke
    /// the user's Sign in with Apple authorization without persisting a token.
    let authorizationCode: String?

    nonisolated init(
        idToken: String,
        nonce: String,
        fullName: String?,
        authorizationCode: String? = nil
    ) {
        self.idToken = idToken
        self.nonce = nonce
        self.fullName = fullName
        self.authorizationCode = authorizationCode
    }
}

nonisolated enum AccountDeletionOutcome: Equatable, Sendable {
    case completed
    case queued
    case manualAppleRevocationRequired
}

/// Describes the profile-photo intent separately from the image bytes so a
/// paired edit can distinguish keeping, replacing, and removing the current
/// private asset.
nonisolated enum AuthProfilePhotoUpdate: Equatable, Sendable {
    case unchanged
    case replace(Data)
    case remove
}

nonisolated struct AuthRouteResolver: Sendable {
    func route(for session: AuthSession?) -> AuthRoute {
        AuthRoute(session: session)
    }
}

nonisolated enum AuthRoute: Equatable, Sendable {
    case signedOut
    case onboarding(AuthSession)
    case limitedAuthenticated(AuthSession)

    init(session: AuthSession?) {
        guard let session else {
            self = .signedOut
            return
        }

        switch session.profileStatus {
        case .needsOnboarding:
            self = .onboarding(session)
        case .complete:
            self = .limitedAuthenticated(session)
        }
    }

    var appState: AppState {
        switch self {
        case .signedOut:
            .unauthenticated
        case .onboarding:
            .onboarding
        case .limitedAuthenticated:
            .limitedAuthenticated
        }
    }

    var session: AuthSession? {
        switch self {
        case .signedOut:
            nil
        case let .onboarding(session), let .limitedAuthenticated(session):
            session
        }
    }
}
