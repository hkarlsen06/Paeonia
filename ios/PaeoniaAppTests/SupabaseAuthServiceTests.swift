import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

struct SupabaseAuthServiceTests {

    @Test func restoreSessionUsesProfileToRequireOnboarding() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.provider == .apple)
        #expect(session?.profileStatus == .needsOnboarding)
        #expect(session?.displayName == "Alex")
    }

    @Test func restoreSessionUsesCompletedProfile() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple, displayName: nil),
            profile: .test(displayName: nil, onboardingCompletedAt: Date())
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.profileStatus == .complete)
        #expect(session?.displayName == nil)
        #expect(session?.timeZoneID == "Europe/Oslo")
        #expect(await gateway.updatedAuthDisplayName == nil)
    }

    @Test func restoreSessionRequiresCompletedProfileTimeZoneTimestamp() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(
                displayName: nil,
                timeZoneUpdatedAt: nil,
                onboardingCompletedAt: Date()
            )
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.profileStatus == .needsOnboarding)
    }

    @Test func restoreSessionPrefersCompletedProfileDisplayName() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple, displayName: "Hjalmar"),
            profile: .test(displayName: "Oda", onboardingCompletedAt: Date())
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.displayName == "Oda")
        #expect(await gateway.updatedAuthDisplayName == nil)
    }

    @Test func appleSignInPassesTokenAndNonceToGateway() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: nil),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.signInWithApple(
            AppleSignInCredential(
                idToken: "id-token",
                nonce: "nonce",
                fullName: "Taylor Swift"
            )
        )

        #expect(await gateway.appleIDToken == "id-token")
        #expect(await gateway.appleNonce == "nonce")
        #expect(session.provider == .apple)
        #expect(session.displayName == "Taylor")
        #expect(await gateway.updatedAuthDisplayName == "Taylor")
        #expect(session.profileStatus == .needsOnboarding)
    }

    @Test func appleSignInUsesOneTimeCredentialNameOverExistingProfileName() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: nil),
            profile: .test(displayName: "Existing", onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.signInWithApple(
            AppleSignInCredential(
                idToken: "id-token",
                nonce: "nonce",
                fullName: "Taylor Swift"
            )
        )

        #expect(session.displayName == "Taylor")
        #expect(await gateway.updatedAuthDisplayName == "Taylor")
    }

    @Test func googleSignInUsesOAuthGatewaySession() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .unknown, displayName: "Riley Chen"),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.signInWithGoogle(
            GoogleSignInCredential(
                idToken: "google-id-token",
                accessToken: "google-access-token"
            )
        )

        #expect(await gateway.googleSignInCallCount == 1)
        #expect(await gateway.googleIDToken == "google-id-token")
        #expect(await gateway.googleAccessToken == "google-access-token")
        #expect(session.provider == .google)
        #expect(session.displayName == "Riley")
        #expect(await gateway.updatedAuthDisplayName == nil)
        #expect(session.profileStatus == .needsOnboarding)
    }

    @Test func completeOnboardingUpdatesProfileFields() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.completeOnboarding(
            displayName: "  Jamie  ",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: nil
        )

        #expect(await gateway.updatedAuthDisplayName == "Jamie")
        #expect(await gateway.updatedTimeZoneID == "Europe/Oslo")
        #expect(session.displayName == "Jamie")
        #expect(session.profileStatus == .complete)
    }

    @Test func completeOnboardingUploadsProfilePhotoBeforeProfileUpdate() async throws {
        let profilePhotoAssetID = try #require(UUID(uuidString: "26D82C6B-281E-4E51-BC3A-A4620282BC9A"))
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple, userID: "7FBBF265-3E75-4010-86CE-29F8A0E68796"),
            profile: .test(displayName: nil, onboardingCompletedAt: nil),
            profilePhotoAssetID: profilePhotoAssetID
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.completeOnboarding(
            displayName: "Jamie",
            timeZoneID: "Europe/Oslo",
            profilePhotoData: Self.makeJPEGData()
        )

        #expect(await gateway.uploadedProfilePhotoUserID == "7FBBF265-3E75-4010-86CE-29F8A0E68796")
        #expect(await gateway.completedProfilePhotoAssetID == profilePhotoAssetID)
        #expect(session.profilePhotoAssetID == profilePhotoAssetID)
        #expect(session.profileStatus == .complete)
    }

    @Test func completeOnboardingRejectsMultipleWords() async {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(displayName: nil, onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        await #expect(throws: AuthServiceError.invalidDisplayName) {
            try await service.completeOnboarding(
                displayName: "Jamie Lee",
                timeZoneID: "Europe/Oslo",
                profilePhotoData: nil
            )
        }
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

    @Test func requestAccountDeletionRequestsBackendThenSignsOut() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: Date())
        )
        let service = SupabaseAuthService(gateway: gateway)

        try await service.requestAccountDeletion()

        #expect(await gateway.requestAccountDeletionCallCount == 1)
        #expect(await gateway.signOutCallCount == 1)
    }

    @Test func requestAccountDeletionRequiresActiveSession() async {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: nil,
            profile: .test(onboardingCompletedAt: Date())
        )
        let service = SupabaseAuthService(gateway: gateway)

        await #expect(throws: AuthServiceError.noActiveSession) {
            try await service.requestAccountDeletion()
        }
        #expect(await gateway.requestAccountDeletionCallCount == 0)
        #expect(await gateway.signOutCallCount == 0)
    }
}

// swiftlint:disable async_without_await
private actor FakeSupabaseAuthGateway: SupabaseAuthGateway {
    private let remoteSession: SupabaseRemoteSession?
    private var profile: SupabaseProfile
    private let profilePhotoAssetID: UUID
    private(set) var appleIDToken: String?
    private(set) var appleNonce: String?
    private(set) var googleSignInCallCount = 0
    private(set) var googleIDToken: String?
    private(set) var googleAccessToken: String?
    private(set) var updatedAuthDisplayName: String?
    private(set) var updatedTimeZoneID: String?
    private(set) var uploadedProfilePhotoUserID: String?
    private(set) var completedProfilePhotoAssetID: UUID?
    private(set) var requestAccountDeletionCallCount = 0
    private(set) var signOutCallCount = 0

    init(
        remoteSession: SupabaseRemoteSession?,
        profile: SupabaseProfile,
        profilePhotoAssetID: UUID? = nil
    ) {
        self.remoteSession = remoteSession
        self.profile = profile
        self.profilePhotoAssetID = profilePhotoAssetID
            ?? UUID(uuidString: "A6B39D76-11D0-4A4D-8B77-5AF09A9E85E1")
            ?? UUID()
    }

    func restoreSession() async throws -> SupabaseRemoteSession? {
        remoteSession
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseRemoteSession {
        appleIDToken = idToken
        appleNonce = nonce
        return remoteSession ?? .test(provider: .apple)
    }

    func signInWithGoogle(
        idToken: String,
        accessToken: String?
    ) async throws -> SupabaseRemoteSession {
        googleSignInCallCount += 1
        googleIDToken = idToken
        googleAccessToken = accessToken
        return remoteSession ?? .test(provider: .google)
    }

    func loadProfile(userID: String) async throws -> SupabaseProfile {
        profile
    }

    func updateAuthDisplayName(_ displayName: String) async throws {
        updatedAuthDisplayName = displayName
        profile = SupabaseProfile(
            userID: profile.userID,
            displayName: displayName,
            timeZoneID: profile.timeZoneID,
            timeZoneUpdatedAt: profile.timeZoneUpdatedAt,
            onboardingCompletedAt: profile.onboardingCompletedAt,
            profilePhotoAssetID: profile.profilePhotoAssetID
        )
    }

    func uploadProfilePhoto(
        userID: String,
        compressedImage: ImageCompressor.CompressedImage
    ) async throws -> UUID {
        uploadedProfilePhotoUserID = userID
        return profilePhotoAssetID
    }

    func completeProfileOnboarding(
        userID: String,
        timeZoneID: String,
        profilePhotoAssetID: UUID?
    ) async throws -> SupabaseProfile {
        updatedTimeZoneID = timeZoneID
        completedProfilePhotoAssetID = profilePhotoAssetID
        profile = SupabaseProfile(
            userID: userID,
            displayName: profile.displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: Date(),
            onboardingCompletedAt: Date(),
            profilePhotoAssetID: profilePhotoAssetID
        )
        return profile
    }

    func requestAccountDeletion() async throws {
        requestAccountDeletionCallCount += 1
    }

    func signOut() async throws {
        signOutCallCount += 1
    }
}
// swiftlint:enable async_without_await

private extension SupabaseRemoteSession {
    static func test(
        provider: AuthProvider,
        userID: String = "user-id",
        displayName: String? = "Alex"
    ) -> SupabaseRemoteSession {
        SupabaseRemoteSession(
            userID: userID,
            provider: provider,
            displayName: displayName
        )
    }
}

private extension SupabaseProfile {
    static func test(
        displayName: String? = "Alex",
        timeZoneID: String? = "Europe/Oslo",
        timeZoneUpdatedAt: Date? = Date(),
        onboardingCompletedAt: Date?,
        profilePhotoAssetID: UUID? = nil
    ) -> SupabaseProfile {
        SupabaseProfile(
            userID: "user-id",
            displayName: displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: timeZoneUpdatedAt,
            onboardingCompletedAt: onboardingCompletedAt,
            profilePhotoAssetID: profilePhotoAssetID
        )
    }
}

private extension SupabaseAuthServiceTests {
    static func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }

        return image.jpegData(compressionQuality: 1) ?? Data()
    }
}
