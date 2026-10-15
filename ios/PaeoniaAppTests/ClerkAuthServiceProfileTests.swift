import Foundation
import Testing
@testable import PaeoniaApp

struct ClerkAuthServiceProfileTests {
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
        try await cache.storeProfilePhotoData(ClerkAuthServiceTests.makeJPEGData(), for: oldAssetID)
        let service = ClerkAuthService(
            gateway: gateway,
            profilePhotoCache: cache,
            profilePhotoInvalidator: invalidator
        )

        let session = try await service.updateProfile(
            displayName: "Jamie",
            profilePhotoUpdate: .replace(ClerkAuthServiceTests.makeJPEGData())
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
                profilePhotoUpdate: .replace(ClerkAuthServiceTests.makeJPEGData())
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
            profilePhotoUpdate: .replace(ClerkAuthServiceTests.makeJPEGData())
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
        try await cache.storeProfilePhotoData(ClerkAuthServiceTests.makeJPEGData(), for: oldAssetID)
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

    @Test func displayNamePolicyAllowsOneOrTwoEnteredWords() {
        #expect(AuthDisplayNamePolicy.validatedName(from: "Jamie") == "Jamie")
        #expect(AuthDisplayNamePolicy.validatedName(from: "  Jamie  ") == "Jamie")
        #expect(AuthDisplayNamePolicy.validatedName(from: "Anne Marie") == "Anne Marie")
        #expect(AuthDisplayNamePolicy.validatedName(from: " Anne \n  Marie ") == "Anne Marie")
        #expect(AuthDisplayNamePolicy.validatedName(from: "Anne Marie Hansen") == nil)
        #expect(AuthDisplayNamePolicy.validatedName(from: "   ") == nil)
    }

    @Test func displayNamePolicyKeepsTheFirstTwoWordsOfProviderNames() {
        #expect(AuthDisplayNamePolicy.normalizedFirstName(from: "Taylor") == "Taylor")
        #expect(AuthDisplayNamePolicy.normalizedFirstName(from: "  Jan   Erik  ") == "Jan Erik")
        #expect(AuthDisplayNamePolicy.normalizedFirstName(from: "Anne Marie Louise") == "Anne Marie")
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
