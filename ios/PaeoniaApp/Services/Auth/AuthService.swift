import Foundation

enum AuthServiceError: Error, Equatable {
    case noActiveSession
    case invalidDisplayName
    case missingConfiguration
    case developmentSignInUnavailable
    case accountDeletionUnavailable
    case invalidProfilePhoto
}

// swiftlint:disable async_without_await

/// A signed-in session restored at launch, with the access state the server
/// answered in the same call.
nonisolated struct RestoredSession: Equatable, Sendable {
    let session: AuthSession
    /// Nil when the server did not answer in time and `session` is the copy
    /// saved on this phone. Access is then loaded with a second call.
    let access: RemoteAccessSnapshot?
}

protocol AuthServicing: Actor {
    func restoreSession() async throws -> RestoredSession?
    /// The session saved on this phone for the signed-in account, read without
    /// a network call. Nil when nobody is signed in or nothing was saved.
    func savedSession() async -> AuthSession?
    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signInForDevelopment() async throws -> AuthSession
    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession
    func updateProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async throws -> AuthSession
    func signOut() async throws
    func requestAccountDeletion(appleAuthorizationCode: String?) async throws -> AccountDeletionOutcome
}

extension AuthServicing {
    func savedSession() async -> AuthSession? {
        nil
    }
}

actor DevelopmentAuthService: AuthServicing {
    private var session: AuthSession?

    init(initialSession: AuthSession? = nil) {
        self.session = initialSession
    }

    func restoreSession() async throws -> RestoredSession? {
        session.map { RestoredSession(session: $0, access: nil) }
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        let session = AuthSession(
            id: "development-apple-user",
            provider: .apple,
            displayName: credential.givenName.flatMap(
                AuthDisplayNamePolicy.normalizedFirstName
            ),
            timeZoneID: nil,
            profilePhotoAssetID: nil,
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func signInWithGoogle() async throws -> AuthSession {
        let session = AuthSession(
            id: "development-google-user",
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
        let session = AuthSession(
            id: "development-user",
            provider: .development,
            displayName: "Local test account",
            timeZoneID: nil,
            profilePhotoAssetID: nil,
            profileStatus: .needsOnboarding
        )
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
        guard let displayName = AuthDisplayNamePolicy.validatedName(from: displayName) else {
            throw AuthServiceError.invalidDisplayName
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
        guard let displayName = AuthDisplayNamePolicy.validatedName(from: displayName) else {
            throw AuthServiceError.invalidDisplayName
        }

        let customProfilePhotoAssetID: UUID? = switch profilePhotoUpdate {
        case .unchanged, .replace:
            session.customProfilePhotoAssetID
        case .remove:
            nil
        }
        let updatedSession = AuthSession(
            id: session.id,
            provider: session.provider,
            displayName: displayName,
            timeZoneID: session.timeZoneID,
            profilePhotoAssetID: nil,
            profileStatus: session.profileStatus,
            customProfilePhotoAssetID: customProfilePhotoAssetID,
            providerProfilePhotoAssetID: session.providerProfilePhotoAssetID
        )
        self.session = updatedSession
        return updatedSession
    }

    func signOut() async throws {
        session = nil
    }

    func requestAccountDeletion(appleAuthorizationCode: String?) async throws -> AccountDeletionOutcome {
        session = nil
        return .completed
    }
}

actor UnavailableAuthService: AuthServicing {
    private let error: AuthServiceError

    init(error: AuthServiceError = .missingConfiguration) {
        self.error = error
    }

    func restoreSession() async throws -> RestoredSession? {
        throw error
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        throw error
    }

    func signInWithGoogle() async throws -> AuthSession {
        throw error
    }

    func signInForDevelopment() async throws -> AuthSession {
        throw AuthServiceError.developmentSignInUnavailable
    }

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession {
        throw error
    }

    func updateProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
        throw error
    }

    func signOut() async throws {
        throw error
    }

    func requestAccountDeletion(appleAuthorizationCode: String?) async throws -> AccountDeletionOutcome {
        throw error
    }
}

enum AuthServiceFactory {
    static func makeDefault() -> any AuthServicing {
        do {
            return try ClerkAuthService.live()
        } catch {
            #if DEBUG
            return DevelopmentAuthService()
            #else
            return UnavailableAuthService()
            #endif
        }
    }
}

// swiftlint:enable async_without_await
