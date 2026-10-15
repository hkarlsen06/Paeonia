import Foundation

extension ClerkAuthService {
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
            profile = try await confirmOnboarding(
                after: error,
                timeZoneID: timeZoneID,
                profilePhotoAssetID: linkedProfilePhotoAssetID,
                newlyUploadedAssetID: newlyUploadedAssetID
            )
        }

        if let previousAssetID = currentProfile.profilePhotoAssetID,
           let newlyUploadedAssetID,
           previousAssetID != newlyUploadedAssetID {
            await retireProfilePhoto(previousAssetID)
        }

        return await makeSession(remoteSession: remoteSession, displayName: trimmedDisplayName, profile: profile)
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
        let newlyUploadedAssetID = try await uploadReplacementPhoto(profilePhotoUpdate, for: currentProfile)
        let linkedAssetID = switch profilePhotoUpdate {
        case .unchanged: currentProfile.profilePhotoAssetID
        case .replace: newlyUploadedAssetID
        case .remove: nil as UUID?
        }

        let profile: RemoteProfile
        do {
            profile = try await gateway.updateProfile(
                displayName: displayName,
                profilePhotoAssetID: linkedAssetID
            )
        } catch {
            profile = try await confirmProfileUpdate(
                after: error,
                displayName: displayName,
                profilePhotoAssetID: linkedAssetID,
                newlyUploadedAssetID: newlyUploadedAssetID
            )
        }

        if let previousAssetID = currentProfile.profilePhotoAssetID,
           previousAssetID != profile.profilePhotoAssetID {
            // Queue the replaced/removed asset strictly after the new profile
            // link succeeds. Failure leaves an inaccessible retained asset and
            // is safer than deleting bytes that may still be linked.
            await retireProfilePhoto(previousAssetID)
        }

        return await makeSession(remoteSession: remoteSession, displayName: displayName, profile: profile)
    }

    /// The session after a profile save. The saved name replaces the one from sign-in.
    private func makeSession(
        remoteSession: RemoteAuthSession,
        displayName: String,
        profile: RemoteProfile
    ) async -> AuthSession {
        await makeSession(
            remoteSession: RemoteAuthSession(
                accountID: remoteSession.accountID,
                provider: remoteSession.provider,
                displayName: displayName
            ),
            profile: profile
        )
    }

    /// Uploads the new photo of a profile edit. Nil when the edit keeps or removes the photo.
    private func uploadReplacementPhoto(
        _ update: AuthProfilePhotoUpdate,
        for profile: RemoteProfile
    ) async throws -> UUID? {
        guard case let .replace(data) = update else { return nil }
        return try await uploadProfilePhoto(userID: profile.userID, data: data)
    }

    /// The update may have committed even when its response was lost or
    /// undecodable. Confirm server state and leave genuine orphan cleanup
    /// to the reference-aware backend sweep.
    private func confirmOnboarding(
        after error: any Error,
        timeZoneID: String,
        profilePhotoAssetID: UUID?,
        newlyUploadedAssetID: UUID?
    ) async throws -> RemoteProfile {
        let confirmedProfile = try? await gateway.loadProfile()
        if let confirmedProfile,
           Self.profile(
               confirmedProfile,
               matchesOnboardingTimeZoneID: timeZoneID,
               profilePhotoAssetID: profilePhotoAssetID
           ) {
            return confirmedProfile
        }
        if confirmedProfile != nil, let newlyUploadedAssetID {
            try? await profilePhotoCache.removeProfilePhotoData(for: newlyUploadedAssetID)
        }
        throw error
    }

    /// A lost or undecodable response is ambiguous: Postgres may already
    /// have committed the update. Confirm canonical state before failing.
    /// Never queue the replacement here; the backend orphan sweep safely
    /// collects genuinely unlinked uploads without risking a live asset.
    private func confirmProfileUpdate(
        after error: any Error,
        displayName: String,
        profilePhotoAssetID: UUID?,
        newlyUploadedAssetID: UUID?
    ) async throws -> RemoteProfile {
        let confirmedProfile = try? await gateway.loadProfile()
        if let confirmedProfile,
           Self.profile(
               confirmedProfile,
               matchesDisplayName: displayName,
               profilePhotoAssetID: profilePhotoAssetID
           ) {
            return confirmedProfile
        }
        if confirmedProfile != nil, let newlyUploadedAssetID {
            try? await profilePhotoCache.removeProfilePhotoData(for: newlyUploadedAssetID)
        }
        throw error
    }

    /// Stops an in-flight read of the replaced immutable asset immediately after
    /// the new link commits; backend cleanup may take longer.
    private func retireProfilePhoto(_ previousAssetID: UUID) async {
        await profilePhotoInvalidator?.invalidate(mediaAssetID: previousAssetID)
        try? await gateway.markMediaForDeletion(previousAssetID)
        try? await profilePhotoCache.removeProfilePhotoData(for: previousAssetID)
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
    func importGoogleAvatarIfAvailable(
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
