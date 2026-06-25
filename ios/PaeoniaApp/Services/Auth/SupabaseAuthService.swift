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
        let oauthDisplayName = remoteSession.displayName.flatMap(
            AuthDisplayNamePolicy.normalizedFirstName
        )
            ?? credential.fullName.flatMap(AuthDisplayNamePolicy.normalizedFirstName)
        if remoteSession.displayName?.trimmedNonEmpty == nil,
           let displayName = credential.fullName.flatMap(AuthDisplayNamePolicy.normalizedFirstName) {
            try await gateway.updateAuthDisplayName(displayName)
        }
        let profile = try await gateway.loadProfile(userID: remoteSession.userID)
        return makeSession(
            remoteSession: SupabaseRemoteSession(
                userID: remoteSession.userID,
                provider: .apple,
                displayName: oauthDisplayName
            ),
            profile: profile
        )
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
        let remoteSession = try await gateway.signInWithGoogle(
            idToken: credential.idToken,
            accessToken: credential.accessToken
        )
        let profile = try await gateway.loadProfile(userID: remoteSession.userID)
        return makeSession(
            remoteSession: SupabaseRemoteSession(
                userID: remoteSession.userID,
                provider: .google,
                displayName: remoteSession.displayName.flatMap(
                    AuthDisplayNamePolicy.normalizedFirstName
                )
            ),
            profile: profile
        )
    }

    func signInForDevelopment() async throws -> AuthSession {
        throw AuthServiceError.developmentSignInUnavailable
    }

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession {
        let trimmedDisplayName = try normalizedDisplayName(displayName)

        guard let remoteSession = try await gateway.restoreSession() else {
            throw AuthServiceError.noActiveSession
        }

        try await gateway.updateAuthDisplayName(trimmedDisplayName)
        let profilePhotoAssetID: UUID?
        if let profilePhotoData {
            let compressedImage = await MainActor.run {
                ImageCompressor.compress(profilePhotoData)
            }
            guard let compressedImage else {
                throw AuthServiceError.invalidProfilePhoto
            }
            profilePhotoAssetID = try await gateway.uploadProfilePhoto(
                userID: remoteSession.userID,
                compressedImage: compressedImage
            )
        } else {
            profilePhotoAssetID = nil
        }

        let profile = try await gateway.completeProfileOnboarding(
            userID: remoteSession.userID,
            timeZoneID: timeZoneID,
            profilePhotoAssetID: profilePhotoAssetID
        )
        return makeSession(
            remoteSession: SupabaseRemoteSession(
                userID: remoteSession.userID,
                provider: remoteSession.provider,
                displayName: trimmedDisplayName
            ),
            profile: profile
        )
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
        let profileStatus = Self.profileStatus(for: profile)
        let displayName = Self.displayName(
            remoteSession: remoteSession,
            profile: profile,
            profileStatus: profileStatus
        )

        return AuthSession(
            id: remoteSession.userID,
            provider: remoteSession.provider,
            displayName: displayName,
            timeZoneID: profile.timeZoneID?.trimmedNonEmpty,
            profilePhotoAssetID: profile.profilePhotoAssetID,
            profileStatus: profileStatus
        )
    }

    private static func profileStatus(for profile: SupabaseProfile) -> AuthProfileStatus {
        if profile.onboardingCompletedAt != nil,
           profile.timeZoneID?.trimmedNonEmpty != nil,
           profile.timeZoneUpdatedAt != nil {
            return .complete
        }

        return .needsOnboarding
    }

    private static func displayName(
        remoteSession: SupabaseRemoteSession,
        profile: SupabaseProfile,
        profileStatus: AuthProfileStatus
    ) -> String? {
        switch profileStatus {
        case .complete:
            profile.displayName.flatMap(AuthDisplayNamePolicy.normalizedFirstName)
        case .needsOnboarding:
            remoteSession.displayName.flatMap(AuthDisplayNamePolicy.normalizedFirstName)
                ?? profile.displayName.flatMap(AuthDisplayNamePolicy.normalizedFirstName)
        }
    }

    private func normalizedDisplayName(_ value: String) throws -> String {
        guard let displayName = AuthDisplayNamePolicy.validatedSingleName(from: value) else {
            throw AuthServiceError.invalidDisplayName
        }

        return displayName
    }
}

// swiftlint:enable async_without_await
