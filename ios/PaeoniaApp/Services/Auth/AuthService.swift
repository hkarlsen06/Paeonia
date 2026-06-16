enum AuthServiceError: Error, Equatable {
    case noActiveSession
}

// swiftlint:disable async_without_await

protocol AuthServicing: Actor {
    func currentSession() async throws -> AuthSession?
    func signInForDevelopment() async throws -> AuthSession
    func completeOnboarding() async throws -> AuthSession
    func signOut() async throws
    func deleteAccount() async throws
}

actor DevelopmentAuthService: AuthServicing {
    private var session: AuthSession?

    init(initialSession: AuthSession? = nil) {
        self.session = initialSession
    }

    func currentSession() async throws -> AuthSession? {
        session
    }

    func signInForDevelopment() async throws -> AuthSession {
        let session = AuthSession(
            id: "development-user",
            provider: .development,
            displayName: "Local test account",
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func completeOnboarding() async throws -> AuthSession {
        guard let session else {
            throw AuthServiceError.noActiveSession
        }

        let completedSession = session.completingOnboarding()
        self.session = completedSession
        return completedSession
    }

    func signOut() async throws {
        session = nil
    }

    func deleteAccount() async throws {
        session = nil
    }
}

// swiftlint:enable async_without_await
