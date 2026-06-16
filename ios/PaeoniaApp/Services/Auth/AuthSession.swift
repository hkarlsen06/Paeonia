struct AuthSession: Equatable, Identifiable, Sendable {
    let id: String
    let provider: AuthProvider
    let displayName: String
    let profileStatus: AuthProfileStatus

    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init(
        id: String,
        provider: AuthProvider,
        displayName: String,
        profileStatus: AuthProfileStatus
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.profileStatus = profileStatus
    }

    nonisolated func completingOnboarding() -> AuthSession {
        AuthSession(
            id: id,
            provider: provider,
            displayName: displayName,
            profileStatus: .complete
        )
    }
}

enum AuthProvider: Equatable, Sendable {
    case apple
    case google
    case passkey
    case development
}

enum AuthProfileStatus: Equatable, Sendable {
    case needsOnboarding
    case complete
}

enum AuthRoute: Equatable, Sendable {
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
