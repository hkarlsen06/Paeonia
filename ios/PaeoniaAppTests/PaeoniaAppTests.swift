import Foundation
import Testing
@testable import PaeoniaApp

// swiftlint:disable async_without_await

struct PaeoniaAppTests {

    @MainActor
    @Test func appStatesRemainOrdered() {
        #expect(AppState.allCases == [
            .launching,
            .unauthenticated,
            .onboarding,
            .limitedAuthenticated,
            .reviewAccess,
            .unpaired,
            .invitePending,
            .paired,
            .pairedPaywalled,
            .entitlementLost,
            .entitlementRestored,
            .relationshipEndedNotice,
            .deletingAccount,
        ])
    }

    @MainActor
    @Test func startRoutesMissingSessionToSignedOut() async throws {
        let syncCoordinator = TestSyncCoordinator()
        let authService = AuthServiceSpy()
        let viewModel = RootViewModel(
            syncCoordinator: syncCoordinator,
            authService: authService
        )

        await viewModel.start()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(viewModel.currentSession == nil)
        #expect(await syncCoordinator.startCallCount == 0)
    }

    @MainActor
    @Test func startRoutesIncompleteProfileToOnboarding() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(session: .test(profileStatus: .needsOnboarding))
        )

        await viewModel.start()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)
        #expect(viewModel.currentSession?.timeZoneID == nil)
    }

    @MainActor
    @Test func completedProfileUsesAccessRouteForVisibleState() async {
        let accessRouteService = StaticAccessRouteService(route: .unpaired)
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService
        )

        await viewModel.start()

        #expect(viewModel.authRoute.appState == .limitedAuthenticated)
        #expect(viewModel.state == .unpaired)
        #expect(await accessRouteService.resolveCallCount == 1)
    }

    @MainActor
    @Test func completedProfilePassesPendingInviteToAccessRoute() async {
        let accessRouteService = StaticAccessRouteService(route: .invitePending)
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test())
        )

        await viewModel.start()

        #expect(viewModel.state == .invitePending)
        #expect(await accessRouteService.receivedHasPendingInvite == [true])
    }

    @MainActor
    @Test func pairingRefreshKeepsCurrentPairingStateWhileAccessRouteResolves() async {
        let accessRouteService = BlockingAccessRouteService(
            routes: [.invitePending, .invitePending],
            blockedCallIndex: 2
        )
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test())
        )

        await viewModel.start()
        #expect(viewModel.state == .invitePending)

        let refreshTask = Task { @MainActor in
            await viewModel.refreshAfterPairingChange()
        }

        await accessRouteService.waitForBlockedResolveToStart()
        #expect(viewModel.state == .invitePending)

        await accessRouteService.releaseBlockedResolve()
        await refreshTask.value

        #expect(viewModel.state == .invitePending)
        #expect(await accessRouteService.resolveCallCount == 2)
    }

    @MainActor
    @Test func staleAccessRefreshCannotOverwriteNewerRoute() async {
        let accessRouteService = BlockingAccessRouteService(
            routes: [.invitePending, .invitePending, .paired],
            blockedCallIndex: 2
        )
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(session: .test(profileStatus: .complete)),
            accessRouteService: accessRouteService,
            inviteStore: TestPairingInviteStore(invite: .test())
        )

        await viewModel.start()
        #expect(viewModel.state == .invitePending)

        let staleRefreshTask = Task { @MainActor in
            await viewModel.refreshAfterPairingChange()
        }
        await accessRouteService.waitForBlockedResolveToStart()

        let latestRefreshTask = Task { @MainActor in
            await viewModel.refreshAfterPairingChange()
        }
        await latestRefreshTask.value
        #expect(viewModel.state == .paired)

        await accessRouteService.releaseBlockedResolve()
        await staleRefreshTask.value

        #expect(viewModel.state == .paired)
        #expect(await accessRouteService.resolveCallCount == 3)
    }

    @MainActor
    @Test func developmentSignInCanCompleteOnboarding() async {
        let syncCoordinator = TestSyncCoordinator()
        let viewModel = RootViewModel(
            syncCoordinator: syncCoordinator,
            authService: AuthServiceSpy()
        )

        await viewModel.signInForDevelopment()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.provider == .development)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)

        await viewModel.completeOnboarding(
            displayName: "Test account",
            timeZoneID: "Europe/Oslo"
        )

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.currentSession?.timeZoneID == "Europe/Oslo")
        #expect(await syncCoordinator.startCallCount == 1)
    }

    @MainActor
    @Test func googleSignInRoutesToOnboarding() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy()
        )

        await viewModel.signInWithGoogle(using: GoogleSignInProviderSpy())

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.provider == .google)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)
    }

    @MainActor
    @Test func cancelledGoogleSignInDoesNotShowFailureNotice() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy()
        )

        await viewModel.signInWithGoogle(
            using: GoogleSignInProviderSpy(error: GoogleSignInServiceError.userCancelled)
        )

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func signOutClearsSession() async throws {
        let authService = AuthServiceSpy(session: .test(profileStatus: .complete))
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: authService
        )

        await viewModel.start()
        await viewModel.signOut()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(try await authService.restoreSession() == nil)
    }

    @MainActor
    @Test func deleteAccountShowsDeletingStateBeforeClearingSession() async throws {
        let authService = BlockingDeleteAuthService()
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: authService
        )

        await viewModel.start()
        #expect(viewModel.state == .limitedAuthenticated)

        let deleteTask = Task { @MainActor in
            await viewModel.deleteAccount()
        }

        await authService.waitForDeleteToStart()
        #expect(viewModel.state == .deletingAccount)

        await authService.releaseDelete()
        await deleteTask.value

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(try await authService.restoreSession() == nil)
    }

    @MainActor
    @Test func deleteFailureRestoresPreviousRoute() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.requestAccountDeletion]
        )
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: authService
        )

        await viewModel.start()
        await viewModel.deleteAccount()

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.notice == .deleteAccountFailed)
    }

    @MainActor
    @Test func deleteFailureRestoresResolvedAccessRoute() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.requestAccountDeletion]
        )
        let accessRouteService = StaticAccessRouteService(route: .unpaired)
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: authService,
            accessRouteService: accessRouteService
        )

        await viewModel.start()
        #expect(viewModel.state == .unpaired)

        await viewModel.deleteAccount()

        #expect(viewModel.state == .unpaired)
        #expect(viewModel.currentSession?.profileStatus == .complete)
        #expect(viewModel.notice == .deleteAccountFailed)
    }

    @MainActor
    @Test func failedSessionLoadFallsBackToSignedOut() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(failingOperations: [.restoreSession])
        )

        await viewModel.start()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(viewModel.notice == .sessionLoadFailed)
    }

    @MainActor
    @Test func dismissNoticeClearsNotice() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(failingOperations: [.restoreSession])
        )

        await viewModel.start()
        #expect(viewModel.notice == .sessionLoadFailed)

        viewModel.dismissNotice()
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test func startRestoresAuthBeforeStartingSync() async {
        let recorder = StartupOrderRecorder()
        let authService = OrderedAuthService(recorder: recorder)
        let syncCoordinator = OrderedSyncCoordinator(recorder: recorder)
        let viewModel = RootViewModel(
            syncCoordinator: syncCoordinator,
            authService: authService
        )

        await viewModel.start()

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(recorder.events == [.restoreSession, .startSync])
    }
}

private actor TestSyncCoordinator: SyncCoordinating {
    private(set) var startCallCount = 0

    func start() {
        startCallCount += 1
    }
}

private actor StaticAccessRouteService: AccessRouteServicing {
    private let route: AccessRoute
    private(set) var resolveCallCount = 0
    private(set) var receivedHasPendingInvite: [Bool] = []

    init(route: AccessRoute) {
        self.route = route
    }

    func resolveRoute(hasPendingInvite: Bool) async throws -> AccessRoute {
        resolveCallCount += 1
        receivedHasPendingInvite.append(hasPendingInvite)
        return route
    }
}

private actor BlockingAccessRouteService: AccessRouteServicing {
    private let routes: [AccessRoute]
    private let blockedCallIndex: Int
    private var blockedResolveStarted = false
    private var blockedResolveStartedContinuation: CheckedContinuation<Void, Never>?
    private var blockedResolveReleaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var resolveCallCount = 0

    init(routes: [AccessRoute], blockedCallIndex: Int) {
        precondition(!routes.isEmpty)
        self.routes = routes
        self.blockedCallIndex = blockedCallIndex
    }

    func waitForBlockedResolveToStart() async {
        if blockedResolveStarted {
            return
        }

        await withCheckedContinuation { continuation in
            blockedResolveStartedContinuation = continuation
        }
    }

    func releaseBlockedResolve() {
        blockedResolveReleaseContinuation?.resume()
        blockedResolveReleaseContinuation = nil
    }

    func resolveRoute(hasPendingInvite: Bool) async throws -> AccessRoute {
        resolveCallCount += 1
        let callIndex = resolveCallCount

        if callIndex == blockedCallIndex {
            blockedResolveStarted = true
            blockedResolveStartedContinuation?.resume()
            blockedResolveStartedContinuation = nil

            await withCheckedContinuation { continuation in
                blockedResolveReleaseContinuation = continuation
            }
        }

        let routeIndex = min(callIndex - 1, routes.count - 1)
        return routes[routeIndex]
    }
}

@MainActor
private final class TestPairingInviteStore: PairingInviteStoring {
    private var invitesByUserID: [String: PairingInvite]

    init(
        invite: PairingInvite? = nil,
        userID: String = AuthSession.test(profileStatus: .complete).id
    ) {
        if let invite {
            self.invitesByUserID = [userID: invite]
        } else {
            self.invitesByUserID = [:]
        }
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        invitesByUserID[userID]
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        invitesByUserID[userID] = invite
    }

    func clearInvite(for userID: String) {
        invitesByUserID[userID] = nil
    }
}

private final class StartupOrderRecorder: @unchecked Sendable {
    enum Event: Equatable {
        case restoreSession
        case startSync
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.withLock {
            recordedEvents
        }
    }

    func record(_ event: Event) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

private actor OrderedSyncCoordinator: SyncCoordinating {
    private let recorder: StartupOrderRecorder

    init(recorder: StartupOrderRecorder) {
        self.recorder = recorder
    }

    func start() {
        recorder.record(.startSync)
    }
}

private actor OrderedAuthService: AuthServicing {
    private let recorder: StartupOrderRecorder

    init(recorder: StartupOrderRecorder) {
        self.recorder = recorder
    }

    func restoreSession() async throws -> AuthSession? {
        recorder.record(.restoreSession)
        return .test(profileStatus: .complete)
    }

    func signInWithApple(_ credential: AppleSignInCredential) async throws -> AuthSession {
        .test(profileStatus: .needsOnboarding)
    }

    func signInWithGoogle(_ credential: GoogleSignInCredential) async throws -> AuthSession {
        AuthSession(
            id: "ordered-google-user",
            provider: .google,
            displayName: nil,
            timeZoneID: nil,
            profileStatus: .needsOnboarding
        )
    }

    func signInForDevelopment() async throws -> AuthSession {
        .test(profileStatus: .needsOnboarding)
    }

    func completeOnboarding(displayName: String, timeZoneID: String) async throws -> AuthSession {
        .test(profileStatus: .complete)
    }

    func signOut() async throws {}

    func requestAccountDeletion() async throws {}
}

private extension PairingInvite {
    static func test() -> PairingInvite {
        PairingInvite(
            id: UUID(uuidString: "0841FAE5-E016-497A-B082-CDF8D4432F30") ?? UUID(),
            code: "01ABCD",
            joinURL: URL(string: "https://paeonia.no/join/01ABCD") ?? URL(fileURLWithPath: "/"),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }
}

// swiftlint:enable async_without_await
