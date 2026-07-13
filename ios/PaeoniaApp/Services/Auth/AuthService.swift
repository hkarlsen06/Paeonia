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

protocol AuthServicing: Actor {
    func restoreSession() async throws -> AuthSession?
    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession
    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession
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

actor DevelopmentAuthService: AuthServicing {
    private var session: AuthSession?

    init(initialSession: AuthSession? = nil) {
        self.session = initialSession
    }

    func restoreSession() async throws -> AuthSession? {
        session
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        let session = AuthSession(
            id: "development-apple-user",
            provider: .apple,
            displayName: credential.fullName.flatMap(
                AuthDisplayNamePolicy.normalizedFirstName
            ),
            timeZoneID: nil,
            profilePhotoAssetID: nil,
            profileStatus: .needsOnboarding
        )
        self.session = session
        return session
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
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
        guard let displayName = AuthDisplayNamePolicy.validatedSingleName(from: displayName) else {
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
        guard let displayName = AuthDisplayNamePolicy.validatedSingleName(from: displayName) else {
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

    func restoreSession() async throws -> AuthSession? {
        throw error
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        throw error
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
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
            return try SupabaseAuthService.live()
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
