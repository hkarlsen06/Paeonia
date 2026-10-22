import ClerkKit
import Foundation

/// The signed-in Clerk account, read without a network call.
nonisolated struct RemoteAuthSession: Equatable, Sendable {
    /// The Clerk user id. It keys the offline session cache. The Paeonia user id
    /// is `RemoteProfile.userID`, which Convex assigns.
    let accountID: String
    let provider: AuthProvider
    let displayName: String?
    /// Transient Google artwork. Paeonia imports it into private storage during
    /// sign-in and never stores this public URL as the user's avatar.
    let providerAvatarURL: URL?

    init(
        accountID: String,
        provider: AuthProvider,
        displayName: String?,
        providerAvatarURL: URL? = nil
    ) {
        self.accountID = accountID
        self.provider = provider
        self.displayName = displayName
        self.providerAvatarURL = providerAvatarURL
    }
}

nonisolated struct RemoteProfile: Codable, Equatable, Sendable {
    let userID: String
    let displayName: String?
    let timeZoneID: String?
    let timeZoneUpdatedAt: Date?
    let onboardingCompletedAt: Date?
    let profilePhotoAssetID: UUID?
    let providerProfilePhotoAssetID: UUID?
    let providerProfilePhotoSource: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case timeZoneID = "time_zone_id"
        case timeZoneUpdatedAt = "time_zone_updated_at"
        case onboardingCompletedAt = "onboarding_completed_at"
        case profilePhotoAssetID = "profile_photo_asset_id"
        case providerProfilePhotoAssetID = "provider_profile_photo_asset_id"
        case providerProfilePhotoSource = "provider_profile_photo_source"
    }
}

/// What a cold launch needs from the server: the profile and the access state,
/// answered by one call.
nonisolated struct RemoteLaunch: Equatable, Sendable {
    let profile: RemoteProfile
    let access: RemoteAccessSnapshot
}

protocol AuthGateway: Actor {
    func restoreSession() async throws -> RemoteAuthSession?
    /// The signed-in Clerk account stored on this phone, read without a network
    /// call and without the debug sign-in ticket.
    func localSession() async -> RemoteAuthSession?
    func signInWithApple(idToken: String) async throws -> RemoteAuthSession
    func signInWithGoogle() async throws -> RemoteAuthSession
    func loadProfile() async throws -> RemoteProfile
    func loadLaunch() async throws -> RemoteLaunch
    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID
    func markMediaForDeletion(_ mediaAssetID: UUID) async throws
    func completeProfileOnboarding(
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile
    func updateProfile(
        displayName: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile
    func updateProviderProfilePhoto(
        profilePhotoAssetID: UUID,
        source: String
    ) async throws -> RemoteProfile
    func requestAccountDeletion(appleAuthorizationCode: String?) async throws -> AccountDeletionOutcome
    func signOut() async throws
}

/// Clerk owns the sign-in session. Convex owns the profile and every other row.
actor LiveAuthGateway: AuthGateway {
    private let client: PaeoniaConvexClient

    init(client: PaeoniaConvexClient) {
        self.client = client
    }

    func restoreSession() async throws -> RemoteAuthSession? {
        #if DEBUG
        await DebugSignInTicket.signInIfGiven()
        #endif
        return await Self.activeClerkSession()
    }

    func localSession() async -> RemoteAuthSession? {
        await Self.activeClerkSession()
    }

    func signInWithApple(idToken: String) async throws -> RemoteAuthSession {
        try await Self.signInWithClerk(fallbackProvider: .apple) {
            try await Clerk.shared.auth.signInWithIdToken(idToken, provider: .apple)
        }
    }

    func signInWithGoogle() async throws -> RemoteAuthSession {
        try await Self.signInWithClerk(fallbackProvider: .google) {
            try await Clerk.shared.auth.signInWithOAuth(provider: .google)
        }
    }

    func loadProfile() async throws -> RemoteProfile {
        // Creates the user row and profile on the first signed-in call, and
        // returns the profile, so no second request is needed.
        let profile: FirstRow<RemoteProfile> = try await client.mutation("identity:ensure_current_user")
        guard let row = profile.row else {
            throw AuthServiceError.noActiveSession
        }
        return row
    }

    func loadLaunch() async throws -> RemoteLaunch {
        // Creates the user row and profile on the first signed-in call, like
        // `loadProfile`, and returns the access state next to the profile.
        let response: LaunchResponse = try await client.mutation("identity:launch")
        guard let profile = response.profile else {
            throw AuthServiceError.noActiveSession
        }
        return RemoteLaunch(profile: profile, access: response.access)
    }

    func completeProfileOnboarding(
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile {
        let profile: FirstRow<RemoteProfile> = try await client.mutation(
            "identity:complete_profile_onboarding",
            args: CompleteProfileOnboardingRequest(
                timeZoneID: timeZoneID,
                profilePhotoAssetID: profilePhotoAssetID
            )
        )
        guard let row = profile.row else {
            throw AuthServiceError.noActiveSession
        }
        return row
    }

    func updateProfile(
        displayName: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile {
        let profile: FirstRow<RemoteProfile> = try await client.mutation(
            "identity:update_own_profile",
            args: UpdateOwnProfileRequest(
                displayName: displayName,
                profilePhotoAssetID: profilePhotoAssetID
            )
        )
        guard let row = profile.row else {
            throw AuthServiceError.noActiveSession
        }
        return row
    }

    func updateProviderProfilePhoto(
        profilePhotoAssetID: UUID,
        source: String
    ) async throws -> RemoteProfile {
        let profile: FirstRow<RemoteProfile> = try await client.mutation(
            "identity:set_own_provider_profile_photo",
            args: UpdateProviderProfilePhotoRequest(
                profilePhotoAssetID: profilePhotoAssetID,
                source: source
            )
        )
        guard let row = profile.row else {
            throw AuthServiceError.noActiveSession
        }
        return row
    }

    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID {
        guard let reservedParentID = UUID(uuidString: userID) else {
            throw AuthServiceError.invalidProfilePhoto
        }
        let reserveOperation = await makeClientOperation()
        let reservations: [MediaUploadReservation] = try await client.mutation(
            "media:create_pending_media_upload",
            args: CreatePendingProfilePhotoUploadRequest(
                operation: reserveOperation,
                reservedParentID: reservedParentID,
                fileExtension: compressedImage.fileExtension
            )
        )
        guard let reservation = reservations.first else {
            throw AuthServiceError.invalidProfilePhoto
        }

        let storageID = try await client.upload(
            compressedImage.data,
            contentType: compressedImage.mediaType,
            to: reservation.uploadURL
        )

        let finalizeOperation = await makeClientOperation()
        let finalized: [FinalizedMediaUploadResponse] = try await client.mutation(
            "media:finalize_media_upload",
            args: FinalizeProfilePhotoUploadRequest(
                reservation: reservation,
                storageID: storageID,
                reservedByClientOperationID: reserveOperation.id,
                operation: finalizeOperation,
                reservedParentID: reservedParentID,
                image: compressedImage
            )
        )
        guard let finalized = finalized.first,
              finalized.uploadStatus == "finalized" else {
            throw AuthServiceError.invalidProfilePhoto
        }

        return finalized.mediaAssetID
    }

    func markMediaForDeletion(_ mediaAssetID: UUID) async throws {
        try await client.mutation(
            "media:mark_media_for_deletion",
            args: MarkMediaForDeletionRequest(mediaAssetID: mediaAssetID)
        )
    }

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        // The delete_account action owns the irreversible database transaction
        // and the Clerk user deletion as one operation. Do not start the
        // mutation separately in the app: losing that first response could
        // otherwise restore paired UI after the database had already
        // tombstoned the account.
        let providerBeforeAttempt = await Self.activeClerkSession()?.provider ?? .unknown
        do {
            return try await invokeAccountDeletion(
                appleAuthorizationCode: appleAuthorizationCode
            )
        } catch {
            // A dropped response is ambiguous: the database stage may have
            // committed. Confirm the idempotent tombstone directly before Root
            // is allowed to restore paired UI, then retry the action once so a
            // still-fresh Apple code gets another revocation attempt.
            let start: AccountDeletionStartResponse
            do {
                start = try await startAccountDeletion()
            } catch {
                // If the first call already deleted the Clerk user before its
                // response disappeared, the token can no longer confirm the
                // idempotent mutation. A missing session is itself a completed
                // boundary.
                if await Self.clerkSessionIsGone() {
                    return providerBeforeAttempt == .apple
                        ? .manualAppleRevocationRequired
                        : .completed
                }
                throw error
            }
            do {
                return try await invokeAccountDeletion(
                    appleAuthorizationCode: appleAuthorizationCode
                )
            } catch {
                return start.authProvider == "apple"
                    ? .manualAppleRevocationRequired
                    : .queued
            }
        }
    }

    func signOut() async throws {
        // Needs the account's token, so it runs before Clerk forgets the session.
        await ConvexPushRegistrationService.disableRegisteredDevice(client: client)
        try await Self.signOutOfClerk()
    }

    private func startAccountDeletion() async throws -> AccountDeletionStartResponse {
        var lastError: (any Error)?
        for attempt in 0..<2 {
            do {
                let start: FirstRow<AccountDeletionStartResponse> = try await client.mutation(
                    "identity:request_account_deletion"
                )
                guard let row = start.row else {
                    throw AuthServiceError.accountDeletionUnavailable
                }
                return row
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 0 {
                    await Task.yield()
                }
            }
        }

        throw lastError ?? AuthServiceError.accountDeletionUnavailable
    }

    private func invokeAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        let response: AccountDeletionFunctionResponse = try await client.action(
            "identity:delete_account",
            args: AccountDeletionFunctionRequest(appleAuthorizationCode: appleAuthorizationCode)
        )

        if response.requiresManualAppleRevocation {
            return .manualAppleRevocationRequired
        }
        return response.authDeleteStatus == "completed" ? .completed : .queued
    }

    private func makeClientOperation() async -> AuthClientOperation {
        await MainActor.run {
            SyncClientOperationFactory.shared.makeOperation()
        }
    }
}

// MARK: - Clerk

private extension LiveAuthGateway {
    @MainActor
    static func signInWithClerk(
        fallbackProvider: AuthProvider,
        _ signIn: () async throws -> TransferFlowResult
    ) async throws -> RemoteAuthSession {
        // The app only starts a sign-in while signed out. A session left over
        // from an earlier failed attempt would make Clerk refuse the new one.
        if Clerk.shared.session != nil {
            // Bounded, so a stalled connection cannot hold up the sign-in sheet.
            _ = try? await AuthNetworkDeadline.run(within: AuthNetworkDeadline.cleanup) { @MainActor in
                try await Clerk.shared.auth.signOut()
            }
        }
        _ = try await signIn()
        // A flow that needs more steps leaves no active session behind.
        guard let session = activeClerkSession(fallbackProvider: fallbackProvider) else {
            throw AuthServiceError.noActiveSession
        }
        return session
    }

    @MainActor
    static func signOutOfClerk() async throws {
        try await Clerk.shared.auth.signOut()
    }

    @MainActor
    static func clerkSessionIsGone() async -> Bool {
        _ = try? await Clerk.shared.refreshClient()
        return Clerk.shared.session == nil
    }

    /// The cached Clerk session. It needs no network, so the app can restore
    /// the signed-in user while offline.
    @MainActor
    static func activeClerkSession(
        fallbackProvider: AuthProvider = .unknown
    ) -> RemoteAuthSession? {
        let clerk = Clerk.shared
        guard let session = clerk.session, session.status == .active, let user = clerk.user else {
            return nil
        }

        let account = user.externalAccounts.first { provider(of: $0) != .unknown }
        return RemoteAuthSession(
            accountID: user.id,
            provider: account.map(provider(of:)) ?? fallbackProvider,
            displayName: (user.firstName ?? account?.firstName)?.trimmedNonEmpty,
            providerAvatarURL: account?.imageUrl.flatMap(URL.init(string:))
        )
    }

    static func provider(of account: ExternalAccount) -> AuthProvider {
        let name = account.provider.lowercased()
        if name.contains("apple") {
            return .apple
        }
        if name.contains("google") {
            return .google
        }
        return .unknown
    }
}

// MARK: - Wire types

nonisolated private struct LaunchResponse: Decodable {
    let profile: RemoteProfile?
    let access: RemoteAccessSnapshot
}

nonisolated private struct AccountDeletionStartResponse: Decodable {
    let authProvider: String

    enum CodingKeys: String, CodingKey {
        case authProvider = "auth_provider"
    }
}

nonisolated private struct AccountDeletionFunctionRequest: Encodable {
    let appleAuthorizationCode: String?
}

nonisolated private struct AccountDeletionFunctionResponse: Decodable {
    let authDeleteStatus: String
    let requiresManualAppleRevocation: Bool
}

nonisolated private struct CompleteProfileOnboardingRequest: Encodable {
    let timeZoneID: String
    let profilePhotoAssetID: UUID?

    enum CodingKeys: String, CodingKey {
        case timeZoneID = "p_time_zone_id"
        case profilePhotoAssetID = "p_profile_photo_asset_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeZoneID, forKey: .timeZoneID)
        try container.encodeIfPresent(profilePhotoAssetID, forKey: .profilePhotoAssetID)
    }
}

nonisolated private struct UpdateOwnProfileRequest: Encodable {
    let displayName: String
    let profilePhotoAssetID: UUID?

    enum CodingKeys: String, CodingKey {
        case displayName = "p_display_name"
        case profilePhotoAssetID = "p_profile_photo_asset_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        if let profilePhotoAssetID {
            try container.encode(profilePhotoAssetID, forKey: .profilePhotoAssetID)
        } else {
            // Paired profile editing supports explicitly removing an existing
            // private photo, so nil must be sent as null rather than omitted.
            try container.encodeNil(forKey: .profilePhotoAssetID)
        }
    }
}

nonisolated private struct UpdateProviderProfilePhotoRequest: Encodable {
    let profilePhotoAssetID: UUID
    let source: String

    enum CodingKeys: String, CodingKey {
        case profilePhotoAssetID = "p_profile_photo_asset_id"
        case source = "p_source"
    }
}

extension String {
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
