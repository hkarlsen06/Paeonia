import Foundation
@testable import PaeoniaApp

// swiftlint:disable async_without_await

actor AuthServiceSpy: AuthServicing {
    enum Operation: Hashable {
        case restoreSession
        case signInWithApple
        case signInWithGoogle
        case signInForDevelopment
        case completeOnboarding
        case updateProfile
        case signOut
        case requestAccountDeletion
    }

    private var session: AuthSession?
    private let failingOperations: Set<Operation>
    private let accountDeletionOutcome: AccountDeletionOutcome

    init(
        session: AuthSession? = nil,
        failingOperations: Set<Operation> = [],
        accountDeletionOutcome: AccountDeletionOutcome = .completed
    ) {
        self.session = session
        self.failingOperations = failingOperations
        self.accountDeletionOutcome = accountDeletionOutcome
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
            profilePhotoAssetID: nil,
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
            profilePhotoAssetID: nil,
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

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession {
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

    func updateProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
        try failIfNeeded(.updateProfile)
        guard let session else {
            throw AuthServiceError.noActiveSession
        }

        let assetID: UUID? = switch profilePhotoUpdate {
        case .unchanged:
            session.customProfilePhotoAssetID
        case .replace:
            UUID(uuidString: "99999999-9999-9999-9999-999999999999")
        case .remove:
            nil
        }
        let updated = AuthSession(
            id: session.id,
            provider: session.provider,
            displayName: displayName,
            timeZoneID: session.timeZoneID,
            profilePhotoAssetID: nil,
            profileStatus: session.profileStatus,
            customProfilePhotoAssetID: assetID,
            providerProfilePhotoAssetID: session.providerProfilePhotoAssetID
        )
        self.session = updated
        return updated
    }

    func signOut() async throws {
        try failIfNeeded(.signOut)
        session = nil
    }

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        try failIfNeeded(.requestAccountDeletion)
        session = nil
        return accountDeletionOutcome
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
            profilePhotoAssetID: nil,
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
            profilePhotoAssetID: nil,
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

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession {
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

    func updateProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
        guard let session else {
            throw AuthServiceError.noActiveSession
        }
        let updated = AuthSession(
            id: session.id,
            provider: session.provider,
            displayName: displayName,
            timeZoneID: session.timeZoneID,
            profilePhotoAssetID: nil,
            profileStatus: session.profileStatus,
            customProfilePhotoAssetID: profilePhotoUpdate == .remove
                ? nil
                : session.customProfilePhotoAssetID,
            providerProfilePhotoAssetID: session.providerProfilePhotoAssetID
        )
        self.session = updated
        return updated
    }

    func signOut() async throws {
        session = nil
    }

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        deleteStarted = true
        deleteStartedContinuation?.resume()
        deleteStartedContinuation = nil

        await withCheckedContinuation { continuation in
            deleteReleaseContinuation = continuation
        }

        session = nil
        return .completed
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

        return credential
    }
}

extension AuthSession {
    nonisolated static func test(
        id: String = "11111111-1111-1111-1111-111111111111",
        profileStatus: AuthProfileStatus
    ) -> AuthSession {
        AuthSession(
            id: id,
            provider: .development,
            displayName: "Test account",
            timeZoneID: profileStatus == .complete ? "Europe/Oslo" : nil,
            profilePhotoAssetID: nil,
            profileStatus: profileStatus
        )
    }
}

// swiftlint:enable async_without_await
