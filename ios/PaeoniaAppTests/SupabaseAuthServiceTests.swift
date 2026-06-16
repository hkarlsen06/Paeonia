import Foundation
import Testing
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
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: Date())
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.restoreSession()

        #expect(session?.profileStatus == .complete)
        #expect(session?.timeZoneID == "Europe/Oslo")
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
                fullName: "Taylor"
            )
        )

        #expect(await gateway.appleIDToken == "id-token")
        #expect(await gateway.appleNonce == "nonce")
        #expect(session.provider == .apple)
        #expect(session.displayName == "Taylor")
        #expect(session.profileStatus == .needsOnboarding)
    }

    @Test func completeOnboardingUpdatesProfileFields() async throws {
        let gateway = FakeSupabaseAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: nil)
        )
        let service = SupabaseAuthService(gateway: gateway)

        let session = try await service.completeOnboarding(
            displayName: "  Jamie  ",
            timeZoneID: "Europe/Oslo"
        )

        #expect(await gateway.updatedDisplayName == "Jamie")
        #expect(await gateway.updatedTimeZoneID == "Europe/Oslo")
        #expect(session.profileStatus == .complete)
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
    private(set) var appleIDToken: String?
    private(set) var appleNonce: String?
    private(set) var updatedDisplayName: String?
    private(set) var updatedTimeZoneID: String?
    private(set) var requestAccountDeletionCallCount = 0
    private(set) var signOutCallCount = 0

    init(remoteSession: SupabaseRemoteSession?, profile: SupabaseProfile) {
        self.remoteSession = remoteSession
        self.profile = profile
    }

    func restoreSession() async throws -> SupabaseRemoteSession? {
        remoteSession
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseRemoteSession {
        appleIDToken = idToken
        appleNonce = nonce
        return remoteSession ?? .test(provider: .apple)
    }

    func loadProfile(userID: String) async throws -> SupabaseProfile {
        profile
    }

    func updateProfile(
        userID: String,
        displayName: String,
        timeZoneID: String
    ) async throws -> SupabaseProfile {
        updatedDisplayName = displayName
        updatedTimeZoneID = timeZoneID
        profile = SupabaseProfile(
            userID: userID,
            displayName: displayName,
            timeZoneID: timeZoneID,
            timeZoneUpdatedAt: Date(),
            onboardingCompletedAt: Date()
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
        displayName: String? = "Alex"
    ) -> SupabaseRemoteSession {
        SupabaseRemoteSession(
            userID: "user-id",
            provider: provider,
            displayName: displayName
        )
    }
}

private extension SupabaseProfile {
    static func test(
        displayName: String? = "Alex",
        onboardingCompletedAt: Date?
    ) -> SupabaseProfile {
        SupabaseProfile(
            userID: "user-id",
            displayName: displayName,
            timeZoneID: "Europe/Oslo",
            timeZoneUpdatedAt: Date(),
            onboardingCompletedAt: onboardingCompletedAt
        )
    }
}
