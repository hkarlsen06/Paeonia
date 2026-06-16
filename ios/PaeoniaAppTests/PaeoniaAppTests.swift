import Testing
@testable import PaeoniaApp

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
        #expect(await syncCoordinator.startCallCount == 1)
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
    }

    @MainActor
    @Test func developmentSignInCanCompleteOnboarding() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy()
        )

        await viewModel.signInForDevelopment()

        #expect(viewModel.state == .onboarding)
        #expect(viewModel.currentSession?.provider == .development)
        #expect(viewModel.currentSession?.profileStatus == .needsOnboarding)

        await viewModel.completeOnboarding()

        #expect(viewModel.state == .limitedAuthenticated)
        #expect(viewModel.currentSession?.profileStatus == .complete)
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
        #expect(try await authService.currentSession() == nil)
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
        #expect(try await authService.currentSession() == nil)
    }

    @MainActor
    @Test func deleteFailureRestoresPreviousRoute() async {
        let authService = AuthServiceSpy(
            session: .test(profileStatus: .complete),
            failingOperations: [.deleteAccount]
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
    @Test func failedSessionLoadFallsBackToSignedOut() async {
        let viewModel = RootViewModel(
            syncCoordinator: TestSyncCoordinator(),
            authService: AuthServiceSpy(failingOperations: [.currentSession])
        )

        await viewModel.start()

        #expect(viewModel.state == .unauthenticated)
        #expect(viewModel.authRoute == .signedOut)
        #expect(viewModel.notice == .sessionLoadFailed)
    }
}

private actor TestSyncCoordinator: SyncCoordinating {
    private(set) var startCallCount = 0

    func start() {
        startCallCount += 1
    }
}
