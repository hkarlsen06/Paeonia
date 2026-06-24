@testable import PaeoniaApp

// swiftlint:disable async_without_await

actor AuthServiceSpy: AuthServicing {
    enum Operation: Hashable {
        case restoreSession
        case signInWithApple
        case signInWithGoogle
        case signInForDevelopment
        case completeOnboarding
        case signOut
        case requestAccountDeletion
    }

    private var session: AuthSession?
    private let failingOperations: Set<Operation>

    init(
        session: AuthSession? = nil,
        failingOperations: Set<Operation> = []
    ) {
        self.session = session
        self.failingOperations = failingOperations
    }

    func restoreSession() async throws -> AuthSession? {
        try failIfNeeded(.restoreSession)
        return session
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        try failIfNeeded(.signInWithApple)

        let session = AuthSession(
            id: "apple-test-user",
            provider: .apple,
            displayName: credential.fullName,
            timeZoneID: nil,
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
        try failIfNeeded(.signInWithGoogle)

        let session = AuthSession(
            id: "google-test-user",
            provider: .google,
            displayName: nil,
            timeZoneID: nil,
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func signInForDevelopment() async throws -> AuthSession {
        try failIfNeeded(.signInForDevelopment)

        let session = AuthSession.test(profileStatus: .needsOnboarding)
        self.session = session
        return session
    }

    func completeOnboarding(displayName: String, timeZoneID: String) async throws -> AuthSession {
        try failIfNeeded(.completeOnboarding)

        guard let session else {
            throw AuthServiceError.noActiveSession
        }

        let completedSession = session.completingOnboarding(
            displayName: displayName,
            timeZoneID: timeZoneID
        )
        self.session = completedSession
        return completedSession
    }

    func signOut() async throws {
        try failIfNeeded(.signOut)
        session = nil
    }

    func requestAccountDeletion() async throws {
        try failIfNeeded(.requestAccountDeletion)
        session = nil
    }

    private func failIfNeeded(_ operation: Operation) throws {
        if failingOperations.contains(operation) {
            throw AuthServiceError.noActiveSession
        }
    }
}

actor BlockingDeleteAuthService: AuthServicing {
    private var session: AuthSession? = .test(profileStatus: .complete)
    private var deleteStarted = false
    private var deleteStartedContinuation: CheckedContinuation<Void, Never>?
    private var deleteReleaseContinuation: CheckedContinuation<Void, Never>?

    func waitForDeleteToStart() async {
        if deleteStarted {
            return
        }

        await withCheckedContinuation { continuation in
            deleteStartedContinuation = continuation
        }
    }

    func releaseDelete() {
        deleteReleaseContinuation?.resume()
        deleteReleaseContinuation = nil
    }

    func restoreSession() async throws -> AuthSession? {
        session
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        let session = AuthSession(
            id: "apple-test-user",
            provider: .apple,
            displayName: credential.fullName,
            timeZoneID: nil,
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
        let session = AuthSession(
            id: "google-test-user",
            provider: .google,
            displayName: nil,
            timeZoneID: nil,
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func signInForDevelopment() async throws -> AuthSession {
        let session = AuthSession.test(profileStatus: .needsOnboarding)
        self.session = session
        return session
    }

    func completeOnboarding(displayName: String, timeZoneID: String) async throws -> AuthSession {
        guard let session else {
            throw AuthServiceError.noActiveSession
        }

        let completedSession = session.completingOnboarding(
            displayName: displayName,
            timeZoneID: timeZoneID
        )
        self.session = completedSession
        return completedSession
    }

    func signOut() async throws {
        session = nil
    }

    func requestAccountDeletion() async throws {
        deleteStarted = true
        deleteStartedContinuation?.resume()
        deleteStartedContinuation = nil

        await withCheckedContinuation { continuation in
            deleteReleaseContinuation = continuation
        }

        session = nil
    }
}

@MainActor
final class GoogleSignInProviderSpy: GoogleSignInProviding {
    private let credential: GoogleSignInCredential
    private let error: Error?

    init(
        credential: GoogleSignInCredential = GoogleSignInCredential(
            idToken: "google-id-token",
            accessToken: "google-access-token"
        ),
        error: Error? = nil
    ) {
        self.credential = credential
        self.error = error
    }

    func signIn() async throws -> GoogleSignInCredential {
        if let error {
            throw error
        }

        credential
    }
}

extension AuthSession {
    nonisolated static func test(profileStatus: AuthProfileStatus) -> AuthSession {
        AuthSession(
            id: "test-user",
            provider: .development,
            displayName: "Test account",
            timeZoneID: profileStatus == .complete ? "Europe/Oslo" : nil,
            profileStatus: profileStatus
        )
    }
}

// swiftlint:enable async_without_await
