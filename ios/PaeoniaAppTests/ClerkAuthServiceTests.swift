import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct ClerkAuthServiceTests {

    @Test func authUserIdentityTreatsUUIDTextCaseAsEquivalent() {
        let uppercase = "EB70D5C2-3F33-4304-8411-3D7C167336B5"
        let lowercase = uppercase.lowercased()

        #expect(AuthUserIdentity.matches(uppercase, lowercase))
        #expect(!AuthUserIdentity.matches(uppercase, "38E6FA64-B11E-41BD-B534-F5F8596C0CA1"))
    }

    @Test func restoreSessionUsesProfileToRequireOnboarding() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.provider == .apple)
        #expect(session?.profileStatus == .needsOnboarding)
        #expect(session?.displayName == "Alex")
    }

    @Test func restoreSessionUsesCompletedProfile() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, displayName: nil),
            profile: .test(displayName: nil, onboardingCompletedAt: Date())
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.profileStatus == .complete)
        #expect(session?.displayName == nil)
        #expect(session?.timeZoneID == "Europe/Oslo")
        #expect(await gateway.updatedProfileDisplayName == nil)
    }

    @Test func restoreSessionRequiresCompletedProfileTimeZoneTimestamp() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(
                displayName: nil,
                timeZoneUpdatedAt: nil,
                onboardingCompletedAt: Date()
            )
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.profileStatus == .needsOnboarding)
    }

    @Test func restoreSessionPrefersCompletedProfileDisplayName() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, displayName: "Hjalmar"),
            profile: .test(displayName: "Oda", onboardingCompletedAt: Date())
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.displayName == "Oda")
        #expect(await gateway.updatedProfileDisplayName == nil)
    }

    @Test func restoreSessionUsesMatchingCachedProfileWhenProfileLoadFails() async throws {
        let cachedSession = AuthSession.test(profileStatus: .complete)
        let sessionCache = FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: URLError(.notConnectedToInternet)
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restoredSession = try await service.restoreSession()

        #expect(restoredSession == cachedSession)
    }

    @Test func restoreSessionPreservesCachedOnboardingRequirementWhenProfileLoadFails() async throws {
        let cachedSession = AuthSession.test(profileStatus: .needsOnboarding)
        let sessionCache = FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: nil),
            loadProfileError: URLError(.networkConnectionLost)
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restoredSession = try await service.restoreSession()

        #expect(restoredSession?.profileStatus == .needsOnboarding)
    }

    @Test func restoreSessionDoesNotUseCachedProfileForAnotherUser() async {
        let sessionCache = FakeAuthSessionCache(
            session: .test(id: "previous-user", profileStatus: .complete),
            accountID: "previous-account"
        )
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "current-account"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: URLError(.notConnectedToInternet)
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        await #expect(throws: URLError.self) {
            try await service.restoreSession()
        }
        #expect(await sessionCache.currentSession == nil)
    }

    @Test(arguments: [502, 503, 429])
    func restoreSessionUsesCachedProfileWhileTheServerIsRestarting(status: Int) async throws {
        let cachedSession = AuthSession.test(profileStatus: .complete)
        let sessionCache = FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: PaeoniaConvexError.http(status: status, body: "Bad gateway")
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restoredSession = try await service.restoreSession()

        #expect(restoredSession == cachedSession)
        #expect(await sessionCache.currentSession == cachedSession)
    }

    @Test func restoreSessionDoesNotUseCacheWhenTheServerRejectsTheRequest() async {
        let sessionCache = FakeAuthSessionCache(session: .test(profileStatus: .complete), accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: PaeoniaConvexError.http(status: 403, body: "Forbidden")
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        await #expect(throws: PaeoniaConvexError.self) {
            try await service.restoreSession()
        }
        #expect(await sessionCache.currentSession == nil)
    }

    @Test func appleSignInGivesUpWhenTheConnectionStalls() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileDelay: .seconds(60)
        )
        let service = ClerkAuthService(
            gateway: gateway,
            sessionCache: FakeAuthSessionCache(),
            signInTimeout: .milliseconds(200)
        )
        let started = ContinuousClock.now

        do {
            _ = try await service.signInWithApple(
                AppleSignInCredential(idToken: "id-token", nonce: "nonce", fullName: nil)
            )
            Issue.record("Expected the stalled sign-in to time out")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }

        // Root shows "We could not sign you in. Try again." for this error.
        #expect(ContinuousClock.now - started < .seconds(10))
        // The half-finished Clerk session is signed out so the retry starts clean.
        #expect(await gateway.signOutCallCount == 1)
    }

    @Test func restoreSessionOpensWithTheCachedProfileWhenTheLoadStalls() async throws {
        let cachedSession = AuthSession.test(profileStatus: .complete)
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileDelay: .seconds(60)
        )
        let service = ClerkAuthService(
            gateway: gateway,
            sessionCache: FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user"),
            restoreTimeout: .milliseconds(200)
        )

        let restoredSession = try await service.restoreSession()

        #expect(restoredSession == cachedSession)
    }

    @Test func restoreSessionDoesNotBringBackASessionSignedOutWhileTheProfileLoaded() async throws {
        let sessionCache = FakeAuthSessionCache()
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date())
        )
        await gateway.endSessionDuringProfileLoad()
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restoredSession = try await service.restoreSession()

        #expect(restoredSession == nil)
        #expect(await sessionCache.currentSession == nil)
    }

    @Test func restoreSessionDoesNotUseCacheWhenBackendRejectsProfile() async {
        let cachedSession = AuthSession.test(profileStatus: .complete)
        let sessionCache = FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: AuthServiceError.invalidProfilePhoto
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        await #expect(throws: AuthServiceError.invalidProfilePhoto) {
            try await service.restoreSession()
        }
        #expect(await sessionCache.currentSession == nil)
    }

    @Test func restoreSessionDoesNotUseCacheWhenProfileLoadIsCancelled() async {
        let cachedSession = AuthSession.test(profileStatus: .complete)
        let sessionCache = FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: URLError(.cancelled)
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        await #expect(throws: URLError.self) {
            try await service.restoreSession()
        }
        #expect(await sessionCache.currentSession == cachedSession)
    }

    @Test func restoreSessionClearsCacheWhenPersistedSessionIsMissing() async throws {
        let sessionCache = FakeAuthSessionCache(
            session: .test(profileStatus: .complete),
            accountID: "clerk-user"
        )
        let gateway = FakeAuthGateway(
            remoteSession: nil,
            profile: .test(onboardingCompletedAt: Date())
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restoredSession = try await service.restoreSession()

        #expect(restoredSession == nil)
        #expect(await sessionCache.currentSession == nil)
    }

    @Test func userDefaultsSessionCacheRoundTripsAndClearsVerifiedProfileState() async {
        let suiteName = "ClerkAuthServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsAuthSessionCache(defaults: defaults)
        let session = AuthSession.test(profileStatus: .complete)

        await cache.save(session, accountID: "clerk-user")

        #expect(await cache.load(accountID: "clerk-user") == session)
        #expect(await cache.load(accountID: "another-account") == nil)

        await cache.clear()
        #expect(await cache.load(accountID: "clerk-user") == nil)
    }

    @Test func appleSignInPassesTokenToGatewayAndSavesCredentialName() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: nil),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.signInWithApple(
            AppleSignInCredential(
                idToken: "id-token",
                nonce: "nonce",
                fullName: "Taylor Swift"
            )
        )

        #expect(await gateway.appleIDToken == "id-token")
        #expect(session.provider == .apple)
        #expect(session.displayName == "Taylor")
        #expect(await gateway.updatedProfileDisplayName == "Taylor")
        #expect(session.profileStatus == .needsOnboarding)
    }

    @Test func appleSignInShowsCredentialNameButKeepsExistingProfileName() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: nil),
            profile: .test(displayName: "Existing", onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.signInWithApple(
            AppleSignInCredential(
                idToken: "id-token",
                nonce: "nonce",
                fullName: "Taylor Swift"
            )
        )

        #expect(session.displayName == "Taylor")
        #expect(await gateway.updatedProfileDisplayName == nil)
    }

    @Test func failedProfileLoadAfterSignInSignsOutOfClerk() async {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: nil),
            loadProfileError: URLError(.notConnectedToInternet)
        )
        let service = ClerkAuthService(gateway: gateway)

        await #expect(throws: URLError.self) {
            try await service.signInWithApple(
                AppleSignInCredential(idToken: "id-token", nonce: "nonce", fullName: nil)
            )
        }
        #expect(await gateway.signOutCallCount == 1)
    }

    @Test func googleSignInUsesOAuthGatewaySession() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: "Riley Chen"),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.signInWithGoogle()

        #expect(await gateway.googleSignInCallCount == 1)
        #expect(session.provider == .google)
        #expect(session.displayName == "Riley")
        #expect(await gateway.updatedProfileDisplayName == nil)
        #expect(session.profileStatus == .needsOnboarding)
    }

    @Test func googleSignInImportsProviderAvatarIntoPrivateProfileAndOnboardingPreservesIt() async throws {
        let importedAssetID = try #require(
            UUID(uuidString: "A6B39D76-11D0-4A4D-8B77-5AF09A9E85E1")
        )
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google, providerAvatarURL: Self.avatarURL),
            profile: .test(displayName: nil, onboardingCompletedAt: nil),
            profilePhotoAssetID: importedAssetID
        )
        let loader = FakeProviderAvatarImageLoader(data: Self.makeJPEGData())
        let service = ClerkAuthService(
            gateway: gateway,
            providerAvatarLoader: loader
        )

        let signedIn = try await service.signInWithGoogle()
        let completed = try await service.completeOnboarding(
            displayName: "Jamie",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: nil
        )

        #expect(await loader.requestedURLs.count == 1)
        #expect(signedIn.profilePhotoAssetID == importedAssetID)
        #expect(await gateway.providerLinkedAssetID == importedAssetID)
        #expect(await gateway.completedProfilePhotoAssetID == nil)
        #expect(completed.profilePhotoAssetID == importedAssetID)
    }

    @Test func googleSignInImportsProviderFallbackBehindExistingCustomPhoto() async throws {
        let existingAssetID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let fallbackAssetID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google, providerAvatarURL: Self.avatarURL),
            profile: .test(
                displayName: "Jamie",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: existingAssetID
            ),
            profilePhotoAssetID: fallbackAssetID
        )
        let loader = FakeProviderAvatarImageLoader(data: Self.makeJPEGData())
        let service = ClerkAuthService(
            gateway: gateway,
            providerAvatarLoader: loader
        )

        let session = try await service.signInWithGoogle()

        #expect(await loader.requestedURLs.count == 1)
        #expect(session.profilePhotoAssetID == existingAssetID)
        #expect(session.customProfilePhotoAssetID == existingAssetID)
        #expect(session.providerProfilePhotoAssetID == fallbackAssetID)
    }

    @Test func completeOnboardingUpdatesProfileFields() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.completeOnboarding(
            displayName: "  Jamie  ",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: nil
        )

        #expect(await gateway.updatedProfileDisplayName == "Jamie")
        #expect(await gateway.updatedTimeZoneID == "Europe/Oslo")
        #expect(session.displayName == "Jamie")
        #expect(session.profileStatus == .complete)
    }

    @Test func completeOnboardingUploadsProfilePhotoBeforeProfileUpdate() async throws {
        let profilePhotoAssetID = try #require(UUID(uuidString: "26D82C6B-281E-4E51-BC3A-A4620282BC9A"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(
                userID: "7FBBF265-3E75-4010-86CE-29F8A0E68796",
                displayName: nil,
                onboardingCompletedAt: nil
            ),
            profilePhotoAssetID: profilePhotoAssetID
        )
        let profilePhotoCache = FakeProfilePhotoImageCache()
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: profilePhotoCache
        )

        let session = try await service.completeOnboarding(
            displayName: "Jamie",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: Self.makeJPEGData()
        )

        #expect(await gateway.uploadedProfilePhotoUserID == "7FBBF265-3E75-4010-86CE-29F8A0E68796")
        #expect(await gateway.completedProfilePhotoAssetID == profilePhotoAssetID)
        #expect(session.profilePhotoAssetID == profilePhotoAssetID)
        #expect(session.profileStatus == .complete)
        #expect(await profilePhotoCache.storedMediaAssetIDs == [profilePhotoAssetID])
        #expect(await profilePhotoCache.profilePhotoData(for: profilePhotoAssetID) != nil)
    }

    @Test func completeOnboardingContinuesWhenProfilePhotoUploadFails() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil),
            uploadShouldFail: true
        )
        let profilePhotoCache = FakeProfilePhotoImageCache()
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: profilePhotoCache
        )

        let session = try await service.completeOnboarding(
            displayName: "Jamie",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: Self.makeJPEGData()
        )

        #expect(session.profileStatus == .complete)
        #expect(session.profilePhotoAssetID == nil)
        #expect(await gateway.completedProfilePhotoAssetID == nil)
        #expect(await profilePhotoCache.storedMediaAssetIDs.isEmpty)
    }

    @Test func completeOnboardingLeavesFailedLinkCleanupToOrphanSweep() async throws {
        let profilePhotoAssetID = try #require(UUID(uuidString: "26D82C6B-281E-4E51-BC3A-A4620282BC9A"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil),
            profilePhotoAssetID: profilePhotoAssetID,
            completeProfileShouldFail: true
        )
        let profilePhotoCache = FakeProfilePhotoImageCache()
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: profilePhotoCache
        )

        await #expect(throws: AuthServiceError.noActiveSession) {
            try await service.completeOnboarding(
                displayName: "Jamie",
                timeZoneID: "Europe/Oslo",
                profilePhotoData: Self.makeJPEGData()
            )
        }

        #expect(await gateway.markedForDeletionAssetID == nil)
        #expect(await profilePhotoCache.profilePhotoData(for: profilePhotoAssetID) == nil)
    }

    @Test func completeOnboardingRejectsMultipleWords() async {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        await #expect(throws: AuthServiceError.invalidDisplayName) {
            try await service.completeOnboarding(
                displayName: "Jamie Lee",
                timeZoneID: "Europe/Oslo",
                profilePhotoData: nil
            )
        }
    }

    @Test func updateProfileLinksReplacementBeforeQueuingOldPhotoDeletion() async throws {
        let oldAssetID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let newAssetID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google),
            profile: .test(
                displayName: "Old",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: oldAssetID
            ),
            profilePhotoAssetID: newAssetID
        )
        let cache = FakeProfilePhotoImageCache()
        let invalidator = FakeProfilePhotoImageInvalidator()
        try await cache.storeProfilePhotoData(Self.makeJPEGData(), for: oldAssetID)
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: cache,
            profilePhotoInvalidator: invalidator
        )

        let session = try await service.updateProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .replace(Self.makeJPEGData())
        )

        #expect(session.displayName == "Jamie")
        #expect(session.profilePhotoAssetID == newAssetID)
        #expect(
            await gateway.profileEvents == [
                "uploaded:\(newAssetID.uuidString)",
                "linked:\(newAssetID.uuidString)",
                "delete:\(oldAssetID.uuidString)",
            ]
        )
        #expect(await cache.profilePhotoData(for: oldAssetID) == nil)
        #expect(await cache.profilePhotoData(for: newAssetID) != nil)
        #expect(await invalidator.invalidatedMediaAssetIDs == [oldAssetID])
    }

    @Test func updateProfileLinkFailureLeavesCleanupToOrphanSweep() async throws {
        let oldAssetID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let newAssetID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google),
            profile: .test(
                displayName: "Old",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: oldAssetID
            ),
            profilePhotoAssetID: newAssetID,
            updateProfileShouldFail: true
        )
        let service = ClerkAuthService(gateway: gateway)

        await #expect(throws: AuthServiceError.noActiveSession) {
            try await service.updateProfile(
                displayName: "Jamie",
                profilePhotoUpdate: .replace(Self.makeJPEGData())
            )
        }

        #expect(await gateway.markedForDeletionAssetIDs.isEmpty)
    }

    @Test func updateProfileRecoversWhenCommittedResponseFails() async throws {
        let oldAssetID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let newAssetID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google),
            profile: .test(
                displayName: "Old",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: oldAssetID
            ),
            profilePhotoAssetID: newAssetID,
            profileUpdateFailsAfterCommit: true
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.updateProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .replace(Self.makeJPEGData())
        )

        #expect(session.displayName == "Jamie")
        #expect(session.customProfilePhotoAssetID == newAssetID)
        #expect(await gateway.markedForDeletionAssetIDs == [oldAssetID])
    }

    @Test func updateProfileClearsOldCacheEvenWhenBackendCleanupMustRetry() async throws {
        let oldAssetID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google),
            profile: .test(
                displayName: "Old",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: oldAssetID
            ),
            markMediaForDeletionShouldFail: true
        )
        let cache = FakeProfilePhotoImageCache()
        let invalidator = FakeProfilePhotoImageInvalidator()
        try await cache.storeProfilePhotoData(Self.makeJPEGData(), for: oldAssetID)
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: cache,
            profilePhotoInvalidator: invalidator
        )

        let session = try await service.updateProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .remove
        )

        #expect(session.profilePhotoAssetID == nil)
        #expect(await gateway.updatedProfilePhotoAssetID == nil)
        #expect(await cache.profilePhotoData(for: oldAssetID) == nil)
        #expect(await invalidator.invalidatedMediaAssetIDs == [oldAssetID])
    }

    @Test func updateProfileRemovingCustomPhotoRevealsProviderFallback() async throws {
        let customAssetID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let fallbackAssetID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google),
            profile: .test(
                displayName: "Jamie",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: customAssetID,
                providerProfilePhotoAssetID: fallbackAssetID
            )
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.updateProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .remove
        )

        #expect(session.customProfilePhotoAssetID == nil)
        #expect(session.providerProfilePhotoAssetID == fallbackAssetID)
        #expect(session.profilePhotoAssetID == fallbackAssetID)
        #expect(await gateway.markedForDeletionAssetIDs == [customAssetID])
    }

    @Test func displayNamePolicyAllowsOnlyOneEnteredWord() {
        #expect(AuthDisplayNamePolicy.validatedSingleName(from: "Jamie") == "Jamie")
        #expect(AuthDisplayNamePolicy.validatedSingleName(from: "  Jamie  ") == "Jamie")
        #expect(AuthDisplayNamePolicy.validatedSingleName(from: "Jamie Lee") == nil)
        #expect(AuthDisplayNamePolicy.validatedSingleName(from: "   ") == nil)
    }

    @Test func displayNamePolicyNormalizesOAuthNamesToFirstName() {
        #expect(AuthDisplayNamePolicy.normalizedFirstName(from: "Taylor Swift") == "Taylor")
        #expect(AuthDisplayNamePolicy.normalizedFirstName(from: "  Riley Chen  ") == "Riley")
        #expect(AuthDisplayNamePolicy.normalizedFirstName(from: "   ") == nil)
    }

    @Test func providerAvatarLoaderAcceptsOnlyHTTPSURLsWithHosts() {
        #expect(
            HTTPSProviderAvatarImageLoader.isSecureURL(
                URL(string: "https://lh3.googleusercontent.com/avatar")
            )
        )
        #expect(
            !HTTPSProviderAvatarImageLoader.isSecureURL(
                URL(string: "http://lh3.googleusercontent.com/avatar")
            )
        )
        #expect(!HTTPSProviderAvatarImageLoader.isSecureURL(URL(string: "https:///avatar")))
    }

    @Test func providerAvatarLoaderKeepsRedirectsOnTheOriginalHTTPSHost() throws {
        let requestedURL = try #require(
            URL(string: "https://lh3.googleusercontent.com/avatar")
        )

        #expect(
            HTTPSProviderAvatarImageLoader.isSecureRedirect(
                from: requestedURL,
                to: URL(string: "https://lh3.googleusercontent.com/new-avatar")
            )
        )
        #expect(
            !HTTPSProviderAvatarImageLoader.isSecureRedirect(
                from: requestedURL,
                to: URL(string: "https://example.com/avatar")
            )
        )
        #expect(
            !HTTPSProviderAvatarImageLoader.isSecureRedirect(
                from: requestedURL,
                to: URL(string: "http://lh3.googleusercontent.com/avatar")
            )
        )
    }

    @Test func requestAccountDeletionPassesAppleCodeThenSignsOut() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: Date()),
            accountDeletionOutcome: .manualAppleRevocationRequired
        )
        let service = ClerkAuthService(gateway: gateway)

        let outcome = try await service.requestAccountDeletion(
            appleAuthorizationCode: "fresh-apple-code"
        )

        #expect(await gateway.requestAccountDeletionCallCount == 1)
        #expect(await gateway.accountDeletionAppleCode == "fresh-apple-code")
        #expect(await gateway.signOutCallCount == 1)
        #expect(outcome == .manualAppleRevocationRequired)
    }

    @Test func signOutClearsCachedProfilePhotosAfterRemoteSignOut() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: Date())
        )
        let profilePhotoCache = FakeProfilePhotoImageCache()
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: profilePhotoCache
        )

        try await service.signOut()

        #expect(await gateway.signOutCallCount == 1)
        #expect(await profilePhotoCache.removeAllCallCount == 1)
    }

    @Test func requestAccountDeletionRequiresActiveSession() async {
        let gateway = FakeAuthGateway(
            remoteSession: nil,
            profile: .test(onboardingCompletedAt: Date())
        )
        let service = ClerkAuthService(gateway: gateway)

        await #expect(throws: AuthServiceError.noActiveSession) {
            try await service.requestAccountDeletion(appleAuthorizationCode: nil)
        }
        #expect(await gateway.requestAccountDeletionCallCount == 0)
        #expect(await gateway.signOutCallCount == 0)
    }
}

// swiftlint:disable async_without_await
private actor FakeAuthGateway: AuthGateway {
    private var remoteSession: RemoteAuthSession?
    /// Ends the Clerk session while `loadProfile` is in flight, like a sign-out tapped meanwhile.
    private var endsSessionDuringProfileLoad = false
    private var profile: RemoteProfile
    private let profilePhotoAssetID: UUID
    private(set) var appleIDToken: String?
    private(set) var googleSignInCallCount = 0
    private(set) var updatedProfileDisplayName: String?
    private(set) var updatedTimeZoneID: String?
    private(set) var uploadedProfilePhotoUserID: String?
    private(set) var completedProfilePhotoAssetID: UUID?
    private(set) var markedForDeletionAssetID: UUID?
    private(set) var markedForDeletionAssetIDs: [UUID] = []
    private(set) var updatedProfilePhotoAssetID: UUID?
    private(set) var providerLinkedAssetID: UUID?
    private(set) var profileEvents: [String] = []
    private(set) var requestAccountDeletionCallCount = 0
    private(set) var accountDeletionAppleCode: String?
    private(set) var signOutCallCount = 0
    private let uploadShouldFail: Bool
    private let loadProfileError: (any Error)?
    /// Makes `loadProfile` hang like a stalled connection, until cancelled.
    private let loadProfileDelay: Duration?
    private let completeProfileShouldFail: Bool
    private let updateProfileShouldFail: Bool
    private let profileUpdateFailsAfterCommit: Bool
    private let markMediaForDeletionShouldFail: Bool
    private let accountDeletionOutcome: AccountDeletionOutcome

    init(
        remoteSession: RemoteAuthSession?,
        profile: RemoteProfile,
        profilePhotoAssetID: UUID? = nil,
        uploadShouldFail: Bool = false,
        loadProfileError: (any Error)? = nil,
        loadProfileDelay: Duration? = nil,
        completeProfileShouldFail: Bool = false,
        updateProfileShouldFail: Bool = false,
        profileUpdateFailsAfterCommit: Bool = false,
        markMediaForDeletionShouldFail: Bool = false,
        accountDeletionOutcome: AccountDeletionOutcome = .completed
    ) {
        self.remoteSession = remoteSession
        self.profile = profile
        self.profilePhotoAssetID = profilePhotoAssetID
            ?? UUID(uuidString: "A6B39D76-11D0-4A4D-8B77-5AF09A9E85E1")
            ?? UUID()
        self.uploadShouldFail = uploadShouldFail
        self.loadProfileError = loadProfileError
        self.loadProfileDelay = loadProfileDelay
        self.completeProfileShouldFail = completeProfileShouldFail
        self.updateProfileShouldFail = updateProfileShouldFail
        self.profileUpdateFailsAfterCommit = profileUpdateFailsAfterCommit
        self.markMediaForDeletionShouldFail = markMediaForDeletionShouldFail
        self.accountDeletionOutcome = accountDeletionOutcome
    }

    func restoreSession() async throws -> RemoteAuthSession? {
        remoteSession
    }

    func signInWithApple(idToken: String) async throws -> RemoteAuthSession {
        appleIDToken = idToken
        return remoteSession ?? .test(provider: .apple)
    }

    func signInWithGoogle() async throws -> RemoteAuthSession {
        googleSignInCallCount += 1
        return remoteSession ?? .test(provider: .google)
    }

    func loadProfile() async throws -> RemoteProfile {
        if let loadProfileDelay {
            try await Task.sleep(for: loadProfileDelay)
        }
        if let loadProfileError {
            throw loadProfileError
        }
        if endsSessionDuringProfileLoad {
            remoteSession = nil
        }
        return profile
    }

    func endSessionDuringProfileLoad() {
        endsSessionDuringProfileLoad = true
    }

    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID {
        if uploadShouldFail {
            throw AuthServiceError.invalidProfilePhoto
        }
        uploadedProfilePhotoUserID = userID
        profileEvents.append("uploaded:\(profilePhotoAssetID.uuidString)")
        return profilePhotoAssetID
    }

    func markMediaForDeletion(_ mediaAssetID: UUID) async throws {
        markedForDeletionAssetID = mediaAssetID
        markedForDeletionAssetIDs.append(mediaAssetID)
        profileEvents.append("delete:\(mediaAssetID.uuidString)")
        if markMediaForDeletionShouldFail {
            throw AuthServiceError.invalidProfilePhoto
        }
    }

    func completeProfileOnboarding(
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile {
        completedProfilePhotoAssetID = profilePhotoAssetID
        if completeProfileShouldFail {
            throw AuthServiceError.noActiveSession
        }
        updatedTimeZoneID = timeZoneID
        profile = RemoteProfile(
            userID: profile.userID,
            displayName: profile.displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: Date(),
            onboardingCompletedAt: Date(),
            profilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoAssetID: profile.providerProfilePhotoAssetID,
            providerProfilePhotoSource: profile.providerProfilePhotoSource
        )
        return profile
    }

    func updateProfile(
        displayName: String,
        profilePhotoAssetID: UUID?
    ) async throws -> RemoteProfile {
        updatedProfileDisplayName = displayName
        updatedProfilePhotoAssetID = profilePhotoAssetID
        profileEvents.append("linked:\(profilePhotoAssetID?.uuidString ?? "nil")")
        if updateProfileShouldFail {
            throw AuthServiceError.noActiveSession
        }
        profile = RemoteProfile(
            userID: profile.userID,
            displayName: displayName,
            timeZoneID: profile.timeZoneID,
            timeZoneUpdatedAt: profile.timeZoneUpdatedAt,
            onboardingCompletedAt: profile.onboardingCompletedAt,
            profilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoAssetID: profile.providerProfilePhotoAssetID,
            providerProfilePhotoSource: profile.providerProfilePhotoSource
        )
        if profileUpdateFailsAfterCommit {
            throw URLError(.networkConnectionLost)
        }
        return profile
    }

    func updateProviderProfilePhoto(
        profilePhotoAssetID: UUID,
        source: String
    ) async throws -> RemoteProfile {
        providerLinkedAssetID = profilePhotoAssetID
        profileEvents.append("provider-linked:\(profilePhotoAssetID.uuidString)")
        if updateProfileShouldFail {
            throw AuthServiceError.noActiveSession
        }
        profile = RemoteProfile(
            userID: profile.userID,
            displayName: profile.displayName,
            timeZoneID: profile.timeZoneID,
            timeZoneUpdatedAt: profile.timeZoneUpdatedAt,
            onboardingCompletedAt: profile.onboardingCompletedAt,
            profilePhotoAssetID: profile.profilePhotoAssetID,
            providerProfilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoSource: source
        )
        return profile
    }

    func requestAccountDeletion(
        appleAuthorizationCode: String?
    ) async throws -> AccountDeletionOutcome {
        requestAccountDeletionCallCount += 1
        accountDeletionAppleCode = appleAuthorizationCode
        return accountDeletionOutcome
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}
// swiftlint:enable async_without_await

private actor FakeProfilePhotoImageCache: ProfilePhotoImageCaching {
    private var storedData: [UUID: Data] = [:]
    private(set) var storedMediaAssetIDs: [UUID] = []
    private(set) var removeAllCallCount = 0

    func profilePhotoData(for mediaAssetID: UUID) async -> Data? {
        storedData[mediaAssetID]
    }

    func storeProfilePhotoData(_ data: Data, for mediaAssetID: UUID) async throws {
        storedData[mediaAssetID] = data
        storedMediaAssetIDs.append(mediaAssetID)
    }

    func removeProfilePhotoData(for mediaAssetID: UUID) async throws {
        storedData[mediaAssetID] = nil
    }

    func removeAllProfilePhotoData() async throws {
        removeAllCallCount += 1
        storedData.removeAll()
    }
}

private actor FakeAuthSessionCache: AuthSessionCaching {
    private(set) var currentSession: AuthSession?
    private var accountID: String?

    init(session: AuthSession? = nil, accountID: String? = nil) {
        currentSession = session
        self.accountID = accountID
    }

    func load(accountID: String) -> AuthSession? {
        guard self.accountID == accountID else {
            return nil
        }
        return currentSession
    }

    func save(_ session: AuthSession, accountID: String) {
        currentSession = session
        self.accountID = accountID
    }

    func clear() {
        currentSession = nil
        accountID = nil
    }
}

private actor FakeProviderAvatarImageLoader: ProviderAvatarImageLoading {
    private let data: Data?
    private(set) var requestedURLs: [URL] = []

    init(data: Data?) {
        self.data = data
    }

    func imageData(from url: URL) async -> Data? {
        requestedURLs.append(url)
        return data
    }
}

private actor FakeProfilePhotoImageInvalidator: ProfilePhotoImageInvalidating {
    private(set) var invalidatedMediaAssetIDs: [UUID] = []

    func invalidate(mediaAssetID: UUID) async {
        invalidatedMediaAssetIDs.append(mediaAssetID)
    }
}

private extension RemoteAuthSession {
    static func test(
        provider: AuthProvider,
        accountID: String = "clerk-user",
        displayName: String? = "Alex",
        providerAvatarURL: URL? = nil
    ) -> RemoteAuthSession {
        RemoteAuthSession(
            accountID: accountID,
            provider: provider,
            displayName: displayName,
            providerAvatarURL: providerAvatarURL
        )
    }
}

private extension RemoteProfile {
    static func test(
        userID: String = "user-id",
        displayName: String? = "Alex",
        timeZoneID: String? = "Europe/Oslo",
        timeZoneUpdatedAt: Date? = Date(),
        onboardingCompletedAt: Date?,
        profilePhotoAssetID: UUID? = nil,
        providerProfilePhotoAssetID: UUID? = nil,
        providerProfilePhotoSource: String? = nil
    ) -> RemoteProfile {
        RemoteProfile(
            userID: userID,
            displayName: displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: timeZoneUpdatedAt,
            onboardingCompletedAt: onboardingCompletedAt,
            profilePhotoAssetID: profilePhotoAssetID,
            providerProfilePhotoAssetID: providerProfilePhotoAssetID,
            providerProfilePhotoSource: providerProfilePhotoSource
        )
    }
}

private extension ClerkAuthServiceTests {
    static let avatarURL = URL(string: "https://lh3.googleusercontent.com/avatar")

    static func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        return image.jpegData(compressionQuality: 1) ?? Data()
    }
}
