import Foundation
#if DEBUG
import OSLog
#endif

// swiftlint:disable async_without_await

actor SupabaseAuthService: AuthServicing {
    private let gateway: any SupabaseAuthGateway
    private let profilePhotoCache: any ProfilePhotoImageCaching
    private let profilePhotoInvalidator: (any ProfilePhotoImageInvalidating)?
    private let providerAvatarLoader: any ProviderAvatarImageLoading
    private let sessionCache: any AuthSessionCaching
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Auth"
    )
    #endif

    init(
        gateway: any SupabaseAuthGateway,
        profilePhotoCache: (any ProfilePhotoImageCaching)? = nil,
        profilePhotoInvalidator: (any ProfilePhotoImageInvalidating)? = nil,
        providerAvatarLoader: (any ProviderAvatarImageLoading)? = nil,
        sessionCache: (any AuthSessionCaching)? = nil
    ) {
        self.gateway = gateway
        self.profilePhotoCache = profilePhotoCache ?? FileProfilePhotoImageCache.live()
        self.profilePhotoInvalidator = profilePhotoInvalidator
            ?? ProfilePhotoImageProviderFactory.cacheInvalidator
        self.providerAvatarLoader = providerAvatarLoader ?? HTTPSProviderAvatarImageLoader()
        self.sessionCache = sessionCache ?? TransientAuthSessionCache()
    }

    static func live() throws -> SupabaseAuthService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabaseAuthService(
            gateway: LiveSupabaseAuthGateway(client: client),
            sessionCache: UserDefaultsAuthSessionCache.shared
        )
    }

    func restoreSession() async throws -> AuthSession? {
        guard let remoteSession = try await gateway.restoreSession() else {
            await sessionCache.clear()
            return nil
        }

        do {
            let profile = try await gateway.loadProfile(userID: remoteSession.userID)
            return await makeSession(remoteSession: remoteSession, profile: profile)
        } catch {
            if AuthSessionFallbackPolicy.isCancellation(error) {
                throw error
            }
            if AuthSessionFallbackPolicy.allowsCachedSession(for: error),
               let cachedSession = await sessionCache.load(userID: remoteSession.userID) {
                return cachedSession
            }
            await sessionCache.clear()
            throw error
        }
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
        return await makeSession(
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
        let loadedProfile = try await gateway.loadProfile(userID: remoteSession.userID)
        let profile = await importGoogleAvatarIfAvailable(
            userID: remoteSession.userID,
            providerAvatarURL: credential.profileImageURL,
            profile: loadedProfile
        )
        return await makeSession(
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

        let currentProfile = try await gateway.loadProfile(userID: remoteSession.userID)

        let newlyUploadedAssetID = await uploadProfilePhotoIfAvailable(
            userID: remoteSession.userID,
            data: profilePhotoData
        )
        let linkedProfilePhotoAssetID = newlyUploadedAssetID
            ?? currentProfile.profilePhotoAssetID

        let profile: SupabaseProfile
        do {
            profile = try await gateway.completeProfileOnboarding(
                userID: remoteSession.userID,
                timeZoneID: timeZoneID,
                profilePhotoAssetID: linkedProfilePhotoAssetID
            )
        } catch {
            // The update may have committed even when its response was lost or
            // undecodable. Confirm server state and leave genuine orphan cleanup
            // to the reference-aware backend sweep.
            let confirmedProfile = try? await gateway.loadProfile(userID: remoteSession.userID)
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
            remoteSession: SupabaseRemoteSession(
                userID: remoteSession.userID,
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

        let currentProfile = try await gateway.loadProfile(userID: remoteSession.userID)
        var newlyUploadedAssetID: UUID?
        let linkedAssetID: UUID?

        switch profilePhotoUpdate {
        case .unchanged:
            linkedAssetID = currentProfile.profilePhotoAssetID
        case let .replace(data):
            let assetID = try await uploadProfilePhoto(
                userID: remoteSession.userID,
                data: data
            )
            newlyUploadedAssetID = assetID
            linkedAssetID = assetID
        case .remove:
            linkedAssetID = nil
        }

        let profile: SupabaseProfile
        do {
            profile = try await gateway.updateProfile(
                userID: remoteSession.userID,
                displayName: displayName,
                profilePhotoAssetID: linkedAssetID
            )
        } catch {
            // A lost or undecodable response is ambiguous: Postgres may already
            // have committed the update. Confirm canonical state before failing.
            // Never queue the replacement here; the backend orphan sweep safely
            // collects genuinely unlinked uploads without risking a live asset.
            let confirmedProfile = try? await gateway.loadProfile(userID: remoteSession.userID)
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

        // The profile row is canonical. Auth metadata is only a future sign-in
        // fallback, so a metadata outage must not undo a successful profile save.
        try? await gateway.updateAuthDisplayName(displayName)

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
            remoteSession: SupabaseRemoteSession(
                userID: remoteSession.userID,
                provider: remoteSession.provider,
                displayName: displayName
            ),
            profile: profile
        )
    }

    /// Compresses and uploads the chosen profile photo, caching it locally on
    /// success. The photo is optional, so any failure here — an image we can't
    /// process or a failed upload — returns `nil` and lets the person finish setup
    /// rather than blocking onboarding.
    private func uploadProfilePhotoIfAvailable(userID: String, data: Data?) async -> UUID? {
        guard let data else {
            return nil
        }

        let compressedImage = await MainActor.run {
            ImageCompressor.compress(data)
        }
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

    /// Paired edits are explicit saves, so an invalid or failed replacement must
    /// surface as an error instead of silently keeping the old image.
    private func uploadProfilePhoto(userID: String, data: Data) async throws -> UUID {
        let compressedImage = await MainActor.run {
            ImageCompressor.compress(data)
        }
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
        profile: SupabaseProfile
    ) async -> SupabaseProfile {
        guard profile.providerProfilePhotoAssetID == nil,
              let providerAvatarURL = Self.trustedGoogleAvatarURL(providerAvatarURL),
              let imageData = await providerAvatarLoader.imageData(from: providerAvatarURL),
              let assetID = await uploadProfilePhotoIfAvailable(userID: userID, data: imageData)
        else {
            return profile
        }

        do {
            return try await gateway.updateProviderProfilePhoto(
                userID: userID,
                profilePhotoAssetID: assetID,
                source: "google"
            )
        } catch {
            let confirmedProfile = try? await gateway.loadProfile(userID: userID)
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
        logger.error("Profile photo \(message, privacy: .public); continuing onboarding without it.")
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
        // The Edge Function may have already removed the Auth user. Supabase
        // still clears its local session before making the remote sign-out call,
        // so a missing remote user is safe to ignore here.
        try? await gateway.signOut()
        await sessionCache.clear()
        try? await profilePhotoCache.removeAllProfilePhotoData()
        return outcome
    }

    private func makeSession(
        remoteSession: SupabaseRemoteSession,
        profile: SupabaseProfile
    ) async -> AuthSession {
        let profileStatus = Self.profileStatus(for: profile)
        let displayName = Self.displayName(
            remoteSession: remoteSession,
            profile: profile,
            profileStatus: profileStatus
        )

        let session = AuthSession(
            id: remoteSession.userID,
            provider: remoteSession.provider,
            displayName: displayName,
            timeZoneID: profile.timeZoneID?.trimmedNonEmpty,
            profilePhotoAssetID: nil,
            profileStatus: profileStatus,
            customProfilePhotoAssetID: profile.profilePhotoAssetID,
            providerProfilePhotoAssetID: profile.providerProfilePhotoAssetID
        )
        await sessionCache.save(session)
        return session
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

    private static func profile(
        _ profile: SupabaseProfile,
        matchesDisplayName displayName: String,
        profilePhotoAssetID: UUID?
    ) -> Bool {
        profile.displayName == displayName
            && profile.profilePhotoAssetID == profilePhotoAssetID
    }

    private static func profile(
        _ profile: SupabaseProfile,
        matchesOnboardingTimeZoneID timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) -> Bool {
        profile.onboardingCompletedAt != nil
            && profile.timeZoneID == timeZoneID
            && profile.timeZoneUpdatedAt != nil
            && profile.profilePhotoAssetID == profilePhotoAssetID
    }

    private func normalizedDisplayName(_ value: String) throws -> String {
        guard let displayName = AuthDisplayNamePolicy.validatedSingleName(from: value) else {
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
