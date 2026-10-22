import Foundation
#if DEBUG
import OSLog
#endif

// swiftlint:disable async_without_await

actor ClerkAuthService: AuthServicing {
    let gateway: any AuthGateway
    let profilePhotoCache: any ProfilePhotoImageCaching
    let profilePhotoInvalidator: (any ProfilePhotoImageInvalidating)?
    let providerAvatarLoader: any ProviderAvatarImageLoading
    private let sessionCache: any AuthSessionCaching
    private let signInTimeout: Duration
    private let restoreTimeout: Duration
    private let cachedRestoreTimeout: Duration
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Auth"
    )
    #endif

    init(
        gateway: any AuthGateway,
        profilePhotoCache: (any ProfilePhotoImageCaching)? = nil,
        profilePhotoInvalidator: (any ProfilePhotoImageInvalidating)? = nil,
        providerAvatarLoader: (any ProviderAvatarImageLoading)? = nil,
        sessionCache: (any AuthSessionCaching)? = nil,
        signInTimeout: Duration = AuthNetworkDeadline.signIn,
        restoreTimeout: Duration = AuthNetworkDeadline.restore,
        cachedRestoreTimeout: Duration = AuthNetworkDeadline.cachedRestore
    ) {
        self.gateway = gateway
        self.signInTimeout = signInTimeout
        self.restoreTimeout = restoreTimeout
        self.cachedRestoreTimeout = cachedRestoreTimeout
        self.profilePhotoCache = profilePhotoCache ?? FileProfilePhotoImageCache.live()
        self.profilePhotoInvalidator = profilePhotoInvalidator
            ?? ProfilePhotoImageProviderFactory.cacheInvalidator
        self.providerAvatarLoader = providerAvatarLoader ?? HTTPSProviderAvatarImageLoader()
        self.sessionCache = sessionCache ?? TransientAuthSessionCache()
    }

    @MainActor
    static func live() throws -> ClerkAuthService {
        guard PaeoniaClerk.configureIfPossible() else {
            throw AuthServiceError.missingConfiguration
        }
        let client = try PaeoniaConvexClientProvider.shared.client()
        return ClerkAuthService(
            gateway: LiveAuthGateway(client: client),
            sessionCache: UserDefaultsAuthSessionCache.shared
        )
    }

    func restoreSession() async throws -> RestoredSession? {
        guard let remoteSession = try await gateway.restoreSession() else {
            await sessionCache.clear()
            return nil
        }

        do {
            // A stalled load times out and opens the app with the cached profile
            // below. With a cached profile to show, the launch waits much less.
            let hasCachedSession = await sessionCache.load(accountID: remoteSession.accountID) != nil
            let gateway = gateway
            let launch = try await AuthNetworkDeadline.run(
                within: hasCachedSession ? cachedRestoreTimeout : restoreTimeout
            ) {
                try await gateway.loadLaunch()
            }
            // A sign-out can finish while the profile loads. Saving the profile
            // now would put the person back on a signed-in screen with no session.
            guard try await gateway.restoreSession()?.accountID == remoteSession.accountID else {
                await sessionCache.clear()
                return nil
            }
            let session = await makeSession(remoteSession: remoteSession, profile: launch.profile)
            return RestoredSession(session: session, access: launch.access)
        } catch {
            if error.isCancellation {
                throw error
            }
            if AuthSessionFallbackPolicy.allowsCachedSession(for: error),
               let cachedSession = await sessionCache.load(accountID: remoteSession.accountID) {
                return RestoredSession(session: cachedSession, access: nil)
            }
            await sessionCache.clear()
            throw error
        }
    }

    func savedSession() async -> AuthSession? {
        guard let remoteSession = await gateway.localSession() else {
            return nil
        }
        return await sessionCache.load(accountID: remoteSession.accountID)
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        // The Apple sheet has closed, so everything from here is network.
        let deadline = ContinuousClock.now + signInTimeout
        let gateway = gateway
        let remoteSession = try await AuthNetworkDeadline.run(until: deadline) {
            try await gateway.signInWithApple(idToken: credential.idToken)
        }
        let appleName = credential.givenName.flatMap(AuthDisplayNamePolicy.normalizedFirstName)
        return try await finishSignIn(
            remoteSession: RemoteAuthSession(
                accountID: remoteSession.accountID,
                provider: .apple,
                displayName: remoteSession.displayName.flatMap(AuthDisplayNamePolicy.normalizedFirstName)
                    ?? appleName
            ),
            fallbackDisplayName: appleName,
            deadline: deadline
        )
    }

    func signInWithGoogle() async throws -> AuthSession {
        // The Google sheet waits for the person, so the deadline starts after it.
        let remoteSession = try await gateway.signInWithGoogle()
        return try await finishSignIn(
            remoteSession: RemoteAuthSession(
                accountID: remoteSession.accountID,
                provider: .google,
                displayName: remoteSession.displayName.flatMap(AuthDisplayNamePolicy.normalizedFirstName),
                providerAvatarURL: remoteSession.providerAvatarURL
            ),
            fallbackDisplayName: nil,
            deadline: .now + signInTimeout
        )
    }

    /// Loads the profile for a fresh Clerk session. When this fails, the Clerk
    /// session is signed out again so the next attempt starts clean instead of
    /// failing with "already signed in".
    private func finishSignIn(
        remoteSession: RemoteAuthSession,
        fallbackDisplayName: String?,
        deadline: ContinuousClock.Instant
    ) async throws -> AuthSession {
        let gateway = gateway
        do {
            var profile = try await AuthNetworkDeadline.run(until: deadline) {
                try await gateway.loadProfile()
            }
            if profile.displayName?.trimmedNonEmpty == nil, let fallbackDisplayName {
                // Apple shares the name only on the first sign-in. Saving it on
                // the profile pre-fills onboarding; a failure only loses that.
                let photoAssetID = profile.profilePhotoAssetID
                profile = (try? await AuthNetworkDeadline.run(until: deadline) {
                    try await gateway.updateProfile(displayName: fallbackDisplayName, profilePhotoAssetID: photoAssetID)
                }) ?? profile
            }
            if remoteSession.provider == .google {
                profile = await importGoogleAvatarIfAvailable(
                    userID: profile.userID,
                    providerAvatarURL: remoteSession.providerAvatarURL,
                    profile: profile
                )
            }
            return await makeSession(remoteSession: remoteSession, profile: profile)
        } catch {
            // Bounded so a stalled connection still ends in the failure banner.
            // A session left behind is signed out before the next attempt.
            _ = try? await AuthNetworkDeadline.run(within: AuthNetworkDeadline.cleanup) {
                try await gateway.signOut()
            }
            throw error
        }
    }

    func signInForDevelopment() async throws -> AuthSession {
        throw AuthServiceError.developmentSignInUnavailable
    }

    func logProfilePhotoIssue(_ message: String) {
        #if DEBUG
        logger.error("Profile photo \(message, privacy: .public); continuing sign-in without it.")
        #endif
    }

    func signOut() async throws {
        try await gateway.signOut()
        await sessionCache.clear()
        try? await profilePhotoCache.removeAllProfilePhotoData()
    }

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        guard try await gateway.restoreSession() != nil else {
            throw AuthServiceError.noActiveSession
        }

        let outcome = try await gateway.requestAccountDeletion(
            appleAuthorizationCode: appleAuthorizationCode
        )
        // The delete_account action already removed the Clerk user, so signing
        // out can fail. Ignore that failure.
        try? await gateway.signOut()
        await sessionCache.clear()
        try? await profilePhotoCache.removeAllProfilePhotoData()
        return outcome
    }

    func makeSession(
        remoteSession: RemoteAuthSession,
        profile: RemoteProfile
    ) async -> AuthSession {
        let profileStatus = Self.profileStatus(for: profile)
        let displayName = Self.displayName(
            remoteSession: remoteSession,
            profile: profile,
            profileStatus: profileStatus
        )

        let session = AuthSession(
            id: profile.userID,
            provider: remoteSession.provider,
            displayName: displayName,
            timeZoneID: profile.timeZoneID?.trimmedNonEmpty,
            profilePhotoAssetID: nil,
            profileStatus: profileStatus,
            customProfilePhotoAssetID: profile.profilePhotoAssetID,
            providerProfilePhotoAssetID: profile.providerProfilePhotoAssetID
        )
        await sessionCache.save(session, accountID: remoteSession.accountID)
        return session
    }

    private static func profileStatus(for profile: RemoteProfile) -> AuthProfileStatus {
        if profile.onboardingCompletedAt != nil,
           profile.timeZoneID?.trimmedNonEmpty != nil,
           profile.timeZoneUpdatedAt != nil {
            return .complete
        }

        return .needsOnboarding
    }

    private static func displayName(
        remoteSession: RemoteAuthSession,
        profile: RemoteProfile,
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
}

// swiftlint:enable async_without_await
