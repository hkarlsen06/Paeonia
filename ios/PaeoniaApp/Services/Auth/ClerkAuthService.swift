import Foundation
#if DEBUG
import OSLog
#endif

// swiftlint:disable async_without_await

actor ClerkAuthService: AuthServicing {
    private let gateway: any AuthGateway
    private let profilePhotoCache: any ProfilePhotoImageCaching
    private let profilePhotoInvalidator: (any ProfilePhotoImageInvalidating)?
    private let providerAvatarLoader: any ProviderAvatarImageLoading
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

    func restoreSession() async throws -> AuthSession? {
        guard let remoteSession = try await gateway.restoreSession() else {
            await sessionCache.clear()
            return nil
        }

        do {
            // A stalled load times out and opens the app with the cached profile
            // below. With a cached profile to show, the launch waits much less.
            let hasCachedSession = await sessionCache.load(accountID: remoteSession.accountID) != nil
            let gateway = gateway
            let profile = try await AuthNetworkDeadline.run(
                within: hasCachedSession ? cachedRestoreTimeout : restoreTimeout
            ) {
                try await gateway.loadProfile()
            }
            // A sign-out can finish while the profile loads. Saving the profile
            // now would put the person back on a signed-in screen with no session.
            guard try await gateway.restoreSession()?.accountID == remoteSession.accountID else {
                await sessionCache.clear()
                return nil
            }
            return await makeSession(remoteSession: remoteSession, profile: profile)
        } catch {
            if AuthSessionFallbackPolicy.isCancellation(error) {
                throw error
            }
            if AuthSessionFallbackPolicy.allowsCachedSession(for: error),
               let cachedSession = await sessionCache.load(accountID: remoteSession.accountID) {
                return cachedSession
            }
            await sessionCache.clear()
            throw error
        }
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

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async throws -> AuthSession {
        let trimmedDisplayName = try normalizedDisplayName(displayName)

        guard let remoteSession = try await gateway.restoreSession() else {
            throw AuthServiceError.noActiveSession
        }

        let loadedProfile = try await gateway.loadProfile()
        // The profile row holds the display name, so save it before onboarding
        // completes. This also keeps the existing photo link.
        let currentProfile = try await gateway.updateProfile(
            displayName: trimmedDisplayName,
            profilePhotoAssetID: loadedProfile.profilePhotoAssetID
        )

        // Setup needs a photo. Without a picked one, the Google photo already on
        // the profile counts. A picked photo that fails to upload fails setup
        // instead of quietly falling back to the Google one.
        var newlyUploadedAssetID: UUID?
        if let profilePhotoData {
            newlyUploadedAssetID = try await uploadProfilePhoto(
                userID: currentProfile.userID,
                data: profilePhotoData
            )
        }
        let linkedProfilePhotoAssetID = newlyUploadedAssetID
            ?? currentProfile.profilePhotoAssetID

        let profile: RemoteProfile
        do {
            profile = try await gateway.completeProfileOnboarding(
                timeZoneID: timeZoneID,
                profilePhotoAssetID: linkedProfilePhotoAssetID
            )
        } catch {
            // The update may have committed even when its response was lost or
            // undecodable. Confirm server state and leave genuine orphan cleanup
            // to the reference-aware backend sweep.
            let confirmedProfile = try? await gateway.loadProfile()
            if let confirmedProfile,
               Self.profile(
                   confirmedProfile,
                   matchesOnboardingTimeZoneID: timeZoneID,
                   profilePhotoAssetID: linkedProfilePhotoAssetID
               ) {
                profile = confirmedProfile
            } else {
                if confirmedProfile != nil, let newlyUploadedAssetID {
                    try? await profilePhotoCache.removeProfilePhotoData(for: newlyUploadedAssetID)
                }
                throw error
            }
        }

        if let previousAssetID = currentProfile.profilePhotoAssetID,
           let newlyUploadedAssetID,
           previousAssetID != newlyUploadedAssetID {
            // Stop an in-flight read of the old immutable asset immediately
            // after the new link commits; backend cleanup may take longer.
            await profilePhotoInvalidator?.invalidate(mediaAssetID: previousAssetID)
            try? await gateway.markMediaForDeletion(previousAssetID)
            try? await profilePhotoCache.removeProfilePhotoData(for: previousAssetID)
        }

        return await makeSession(
            remoteSession: RemoteAuthSession(
                accountID: remoteSession.accountID,
                provider: remoteSession.provider,
                displayName: trimmedDisplayName
            ),
            profile: profile
        )
    }

    func updateProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async throws -> AuthSession {
        let displayName = try normalizedDisplayName(displayName)
        guard let remoteSession = try await gateway.restoreSession() else {
            throw AuthServiceError.noActiveSession
        }

        let currentProfile = try await gateway.loadProfile()
        var newlyUploadedAssetID: UUID?
        let linkedAssetID: UUID?

        switch profilePhotoUpdate {
        case .unchanged:
            linkedAssetID = currentProfile.profilePhotoAssetID
        case let .replace(data):
            let assetID = try await uploadProfilePhoto(
                userID: currentProfile.userID,
                data: data
            )
            newlyUploadedAssetID = assetID
            linkedAssetID = assetID
        case .remove:
            linkedAssetID = nil
        }

        let profile: RemoteProfile
        do {
            profile = try await gateway.updateProfile(
                displayName: displayName,
                profilePhotoAssetID: linkedAssetID
            )
        } catch {
            // A lost or undecodable response is ambiguous: Postgres may already
            // have committed the update. Confirm canonical state before failing.
            // Never queue the replacement here; the backend orphan sweep safely
            // collects genuinely unlinked uploads without risking a live asset.
            let confirmedProfile = try? await gateway.loadProfile()
            if let confirmedProfile,
               Self.profile(
                   confirmedProfile,
                   matchesDisplayName: displayName,
                   profilePhotoAssetID: linkedAssetID
               ) {
                profile = confirmedProfile
            } else {
                if confirmedProfile != nil, let newlyUploadedAssetID {
                    try? await profilePhotoCache.removeProfilePhotoData(for: newlyUploadedAssetID)
                }
                throw error
            }
        }

        if let previousAssetID = currentProfile.profilePhotoAssetID,
           previousAssetID != profile.profilePhotoAssetID {
            // Queue the replaced/removed asset strictly after the new profile
            // link succeeds. Failure leaves an inaccessible retained asset and
            // is safer than deleting bytes that may still be linked.
            await profilePhotoInvalidator?.invalidate(mediaAssetID: previousAssetID)
            try? await gateway.markMediaForDeletion(previousAssetID)
            try? await profilePhotoCache.removeProfilePhotoData(for: previousAssetID)
        }

        return await makeSession(
            remoteSession: RemoteAuthSession(
                accountID: remoteSession.accountID,
                provider: remoteSession.provider,
                displayName: displayName
            ),
            profile: profile
        )
    }

    /// Compresses and uploads the Google photo, caching it locally on success.
    /// It is only a fallback, so any failure here returns `nil` and lets sign-in
    /// finish without it.
    private func uploadProfilePhotoIfAvailable(userID: String, data: Data) async -> UUID? {
        // Runs on this actor, off the main thread, so resizing never stalls the UI.
        let compressedImage = ImageCompressor.compress(data)
        guard let compressedImage else {
            logProfilePhotoIssue("could not be processed")
            return nil
        }

        do {
            let assetID = try await gateway.uploadProfilePhoto(
                userID: userID,
                compressedImage: compressedImage
            )
            try? await profilePhotoCache.storeProfilePhotoData(compressedImage.data, for: assetID)
            return assetID
        } catch {
            logProfilePhotoIssue("failed to upload: \(error)")
            return nil
        }
    }

    /// Setup and profile edits are explicit saves, so an invalid or failed photo
    /// must surface as an error instead of silently keeping the old image or none.
    private func uploadProfilePhoto(userID: String, data: Data) async throws -> UUID {
        // Runs on this actor, off the main thread, so resizing never stalls the UI.
        let compressedImage = ImageCompressor.compress(data)
        guard let compressedImage else {
            throw AuthServiceError.invalidProfilePhoto
        }

        let assetID = try await gateway.uploadProfilePhoto(
            userID: userID,
            compressedImage: compressedImage
        )
        try? await profilePhotoCache.storeProfilePhotoData(compressedImage.data, for: assetID)
        return assetID
    }

    /// Best-effort Google fallback for both new and previously onboarded users.
    /// It is imported even when a custom photo is active so removing that custom
    /// override can reveal the fallback immediately. The provider URL is consumed
    /// only during sign-in and is never persisted.
    private func importGoogleAvatarIfAvailable(
        userID: String,
        providerAvatarURL: URL?,
        profile: RemoteProfile
    ) async -> RemoteProfile {
        guard profile.providerProfilePhotoAssetID == nil,
              let providerAvatarURL = Self.trustedGoogleAvatarURL(providerAvatarURL),
              let imageData = await providerAvatarLoader.imageData(from: providerAvatarURL),
              let assetID = await uploadProfilePhotoIfAvailable(userID: userID, data: imageData)
        else {
            return profile
        }

        do {
            return try await gateway.updateProviderProfilePhoto(
                profilePhotoAssetID: assetID,
                source: "google"
            )
        } catch {
            let confirmedProfile = try? await gateway.loadProfile()
            if let confirmedProfile {
                if confirmedProfile.providerProfilePhotoAssetID == assetID,
                   confirmedProfile.providerProfilePhotoSource == "google" {
                    return confirmedProfile
                }
                try? await profilePhotoCache.removeProfilePhotoData(for: assetID)
            }
            return profile
        }
    }

    private func logProfilePhotoIssue(_ message: String) {
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

    private func makeSession(
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

    private static func profile(
        _ profile: RemoteProfile,
        matchesDisplayName displayName: String,
        profilePhotoAssetID: UUID?
    ) -> Bool {
        profile.displayName == displayName
            && profile.profilePhotoAssetID == profilePhotoAssetID
    }

    private static func profile(
        _ profile: RemoteProfile,
        matchesOnboardingTimeZoneID timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) -> Bool {
        profile.onboardingCompletedAt != nil
            && profile.timeZoneID == timeZoneID
            && profile.timeZoneUpdatedAt != nil
            && profile.profilePhotoAssetID == profilePhotoAssetID
    }

    private func normalizedDisplayName(_ value: String) throws -> String {
        guard let displayName = AuthDisplayNamePolicy.validatedName(from: value) else {
            throw AuthServiceError.invalidDisplayName
        }

        return displayName
    }

    private static func trustedGoogleAvatarURL(_ url: URL?) -> URL? {
        guard HTTPSProviderAvatarImageLoader.isSecureURL(url),
              let url,
              let host = url.host?.lowercased(),
              host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com")
        else {
            return nil
        }

        return url
    }
}

// swiftlint:enable async_without_await
