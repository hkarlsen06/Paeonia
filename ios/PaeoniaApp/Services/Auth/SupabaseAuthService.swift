import Foundation

// swiftlint:disable async_without_await

actor SupabaseAuthService: AuthServicing {
    private let gateway: any SupabaseAuthGateway

    init(gateway: any SupabaseAuthGateway) {
        self.gateway = gateway
    }

    static func live() throws -> SupabaseAuthService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabaseAuthService(gateway: LiveSupabaseAuthGateway(client: client))
    }

    func restoreSession() async throws -> AuthSession? {
        guard let remoteSession = try await gateway.restoreSession() else {
            return nil
        }

        let profile = try await gateway.loadProfile(userID: remoteSession.userID)
        return makeSession(remoteSession: remoteSession, profile: profile)
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        let remoteSession = try await gateway.signInWithApple(
            idToken: credential.idToken,
            nonce: credential.nonce
        )
        let profile = try await gateway.loadProfile(userID: remoteSession.userID)
        return makeSession(
            remoteSession: SupabaseRemoteSession(
                userID: remoteSession.userID,
                provider: .apple,
                displayName: remoteSession.displayName ?? credential.fullName
            ),
            profile: profile
        )
    }

    func signInForDevelopment() async throws -> AuthSession {
        throw AuthServiceError.developmentSignInUnavailable
    }

    func completeOnboarding(displayName: String, timeZoneID: String) async throws -> AuthSession {
        let trimmedDisplayName = try normalizedDisplayName(displayName)

        guard let remoteSession = try await gateway.restoreSession() else {
            throw AuthServiceError.noActiveSession
        }

        let profile = try await gateway.updateProfile(
            userID: remoteSession.userID,
            displayName: trimmedDisplayName,
            timeZoneID: timeZoneID
        )
        return makeSession(remoteSession: remoteSession, profile: profile)
    }

    func signOut() async throws {
        try await gateway.signOut()
    }

    func requestAccountDeletion() async throws {
        guard try await gateway.restoreSession() != nil else {
            throw AuthServiceError.noActiveSession
        }

        try await gateway.requestAccountDeletion()
        try await gateway.signOut()
    }

    private func makeSession(
        remoteSession: SupabaseRemoteSession,
        profile: SupabaseProfile
    ) -> AuthSession {
        let displayName = profile.displayName?.trimmedNonEmpty
            ?? remoteSession.displayName?.trimmedNonEmpty
        let profileStatus = Self.profileStatus(for: profile)

        return AuthSession(
            id: remoteSession.userID,
            provider: remoteSession.provider,
            displayName: displayName,
            timeZoneID: profile.timeZoneID?.trimmedNonEmpty,
            profileStatus: profileStatus
        )
    }

    private static func profileStatus(for profile: SupabaseProfile) -> AuthProfileStatus {
        if profile.onboardingCompletedAt != nil,
           profile.displayName?.trimmedNonEmpty != nil,
           profile.timeZoneID?.trimmedNonEmpty != nil {
            return .complete
        }

        return .needsOnboarding
    }

    private func normalizedDisplayName(_ value: String) throws -> String {
        guard let displayName = value.trimmedNonEmpty else {
            throw AuthServiceError.noActiveSession
        }

        return String(displayName.prefix(80))
    }
}

// swiftlint:enable async_without_await
