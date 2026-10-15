import Foundation
import Testing
@testable import PaeoniaApp

struct ClerkAuthServiceSignInTests {
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
                givenName: "Anne Marie"
            )
        )

        #expect(await gateway.appleIDToken == "id-token")
        #expect(session.provider == .apple)
        #expect(session.displayName == "Anne Marie")
        #expect(await gateway.updatedProfileDisplayName == "Anne Marie")
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
                givenName: "Taylor"
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
                AppleSignInCredential(idToken: "id-token", nonce: "nonce", givenName: nil)
            )
        }
        #expect(await gateway.signOutCallCount == 1)
    }

    @Test func googleSignInUsesOAuthGatewaySession() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: "Riley"),
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

    @Test func googleSignInImportsProviderAvatarIntoPrivateProfileAndOnboardingKeepsIt() async throws {
        let importedAssetID = try #require(
            UUID(uuidString: "A6B39D76-11D0-4A4D-8B77-5AF09A9E85E1")
        )
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .google, providerAvatarURL: ClerkAuthServiceTests.avatarURL),
            profile: .test(displayName: nil, onboardingCompletedAt: nil),
            profilePhotoAssetID: importedAssetID
        )
        let loader = FakeProviderAvatarImageLoader(data: ClerkAuthServiceTests.makeJPEGData())
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
            remoteSession: .test(provider: .google, providerAvatarURL: ClerkAuthServiceTests.avatarURL),
            profile: .test(
                displayName: "Jamie",
                onboardingCompletedAt: Date(),
                profilePhotoAssetID: existingAssetID
            ),
            profilePhotoAssetID: fallbackAssetID
        )
        let loader = FakeProviderAvatarImageLoader(data: ClerkAuthServiceTests.makeJPEGData())
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
            displayName: "  Anne   Marie  ",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: ClerkAuthServiceTests.makeJPEGData()
        )

        #expect(await gateway.updatedProfileDisplayName == "Anne Marie")
        #expect(await gateway.updatedTimeZoneID == "Europe/Oslo")
        #expect(session.displayName == "Anne Marie")
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
            profilePhotoData: ClerkAuthServiceTests.makeJPEGData()
        )

        #expect(await gateway.uploadedProfilePhotoUserID == "7FBBF265-3E75-4010-86CE-29F8A0E68796")
        #expect(await gateway.completedProfilePhotoAssetID == profilePhotoAssetID)
        #expect(session.profilePhotoAssetID == profilePhotoAssetID)
        #expect(session.profileStatus == .complete)
        #expect(await profilePhotoCache.storedMediaAssetIDs == [profilePhotoAssetID])
        #expect(await profilePhotoCache.profilePhotoData(for: profilePhotoAssetID) != nil)
    }

    @Test func completeOnboardingFailsWhenProfilePhotoUploadFails() async {
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

        await #expect(throws: AuthServiceError.invalidProfilePhoto) {
            try await service.completeOnboarding(
                displayName: "Jamie",
                timeZoneID: "Europe/Oslo",
                profilePhotoData: ClerkAuthServiceTests.makeJPEGData()
            )
        }

        #expect(await gateway.updatedTimeZoneID == nil)
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
                profilePhotoData: ClerkAuthServiceTests.makeJPEGData()
            )
        }

        #expect(await gateway.markedForDeletionAssetID == nil)
        #expect(await profilePhotoCache.profilePhotoData(for: profilePhotoAssetID) == nil)
    }

    @Test func completeOnboardingRejectsMoreThanTwoWords() async {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = ClerkAuthService(gateway: gateway)

        await #expect(throws: AuthServiceError.invalidDisplayName) {
            try await service.completeOnboarding(
                displayName: "Jamie Lee Hansen",
                timeZoneID: "Europe/Oslo",
                profilePhotoData: ClerkAuthServiceTests.makeJPEGData()
            )
        }
    }
}
