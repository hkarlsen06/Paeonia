import Foundation
import Testing
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

        let session = try await service.restoreSession()?.session

        #expect(session?.provider == .apple)
        #expect(session?.profileStatus == .needsOnboarding)
        #expect(session?.displayName == "Alex")
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

        let session = try await service.restoreSession()?.session

        #expect(session?.profileStatus == .needsOnboarding)
    }

    @Test func restoreSessionPrefersCompletedProfileDisplayName() async throws {
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, displayName: "Hjalmar"),
            profile: .test(displayName: "Oda", onboardingCompletedAt: Date())
        )
        let service = ClerkAuthService(gateway: gateway)

        let session = try await service.restoreSession()?.session

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

        let restoredSession = try await service.restoreSession()?.session

        #expect(restoredSession == cachedSession)
    }

    @Test func restoreSessionReturnsTheAccessStateFromTheSameCall() async throws {
        let userID = UUID()
        let access = RemoteAccessSnapshot.pairedForFlowTest(ownerUserID: userID)
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple),
            profile: .test(onboardingCompletedAt: Date()),
            launchAccess: access
        )
        let service = ClerkAuthService(gateway: gateway)

        let restored = try await service.restoreSession()

        #expect(restored?.access == access)
    }

    @Test func restoreSessionHasNoAccessStateWhenItFallsBackToTheCachedProfile() async throws {
        let sessionCache = FakeAuthSessionCache(session: .test(profileStatus: .complete), accountID: "clerk-user")
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date()),
            loadProfileError: URLError(.timedOut)
        )
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restored = try await service.restoreSession()

        #expect(restored != nil)
        #expect(restored?.access == nil)
    }

    @Test func savedSessionIsTheCachedProfileOfTheSignedInAccountOnly() async {
        let cachedSession = AuthSession.test(profileStatus: .complete)
        let sessionCache = FakeAuthSessionCache(session: cachedSession, accountID: "clerk-user")
        let signedIn = ClerkAuthService(
            gateway: FakeAuthGateway(
                remoteSession: .test(provider: .apple, accountID: "clerk-user"),
                profile: .test(onboardingCompletedAt: Date())
            ),
            sessionCache: sessionCache
        )
        let otherAccount = ClerkAuthService(
            gateway: FakeAuthGateway(
                remoteSession: .test(provider: .apple, accountID: "another-user"),
                profile: .test(onboardingCompletedAt: Date())
            ),
            sessionCache: sessionCache
        )
        let signedOut = ClerkAuthService(
            gateway: FakeAuthGateway(remoteSession: nil, profile: .test(onboardingCompletedAt: Date())),
            sessionCache: sessionCache
        )

        #expect(await signedIn.savedSession() == cachedSession)
        #expect(await otherAccount.savedSession() == nil)
        #expect(await signedOut.savedSession() == nil)
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

        let restoredSession = try await service.restoreSession()?.session

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
                AppleSignInCredential(idToken: "id-token", nonce: "nonce", givenName: nil)
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
            restoreTimeout: .seconds(30),
            cachedRestoreTimeout: .milliseconds(200)
        )
        let started = ContinuousClock.now

        let restoredSession = try await service.restoreSession()?.session

        #expect(restoredSession == cachedSession)
        // The saved profile shortens the wait instead of holding the launch screen.
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func restoreSessionDoesNotBringBackASessionSignedOutWhileTheProfileLoaded() async throws {
        let sessionCache = FakeAuthSessionCache()
        let gateway = FakeAuthGateway(
            remoteSession: .test(provider: .apple, accountID: "clerk-user"),
            profile: .test(onboardingCompletedAt: Date())
        )
        await gateway.endSessionDuringProfileLoad()
        let service = ClerkAuthService(gateway: gateway, sessionCache: sessionCache)

        let restoredSession = try await service.restoreSession()?.session

        #expect(restoredSession == nil)
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

        let restoredSession = try await service.restoreSession()?.session

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
}
