import Observation

enum RootNotice: Equatable {
    case sessionLoadFailed
    case signInFailed
    case onboardingFailed
    case signOutFailed
    case deleteAccountFailed
}

@MainActor
@Observable
final class RootViewModel {

    private let syncCoordinator: any SyncCoordinating
    private let authService: any AuthServicing

    private(set) var state: AppState = .launching
    private(set) var authRoute: AuthRoute = .signedOut
    private(set) var isWorking = false
    private(set) var notice: RootNotice?
    private var hasStartedSync = false

    var currentSession: AuthSession? {
        authRoute.session
    }

    init(
        syncCoordinator: (any SyncCoordinating)? = nil,
        authService: (any AuthServicing)? = nil
    ) {
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator()
        self.authService = authService ?? AuthServiceFactory.makeDefault()
    }

    func start() async {
        await refreshAuthRoute()
        await startSyncIfNeeded()
    }

    func signInWithApple(using appleSignInProvider: any AppleSignInProviding) async {
        await performAuthAction(failureNotice: .signInFailed) {
            let credential = try await appleSignInProvider.signIn()
            let session = try await authService.signInWithApple(credential)
            apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signInWithGoogle(using googleSignInProvider: any GoogleSignInProviding) async {
        await performAuthAction(failureNotice: .signInFailed) {
            let credential = try await googleSignInProvider.signIn()
            let session = try await authService.signInWithGoogle(credential)
            apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signInForDevelopment() async {
        await performAuthAction(failureNotice: .signInFailed) {
            let session = try await authService.signInForDevelopment()
            apply(AuthRoute(session: session))
        }
    }

    /// Clears the current notice. Used when the user dismisses the system alert.
    func dismissNotice() {
        notice = nil
    }

    func completeOnboarding(displayName: String, timeZoneID: String) async {
        await performAuthAction(failureNotice: .onboardingFailed) {
            let session = try await authService.completeOnboarding(
                displayName: displayName,
                timeZoneID: timeZoneID
            )
            apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signOut() async {
        await performAuthAction(failureNotice: .signOutFailed) {
            try await authService.signOut()
            apply(.signedOut)
            hasStartedSync = false
        }
    }

    func deleteAccount() async {
        guard !isWorking else {
            return
        }

        let previousRoute = authRoute
        isWorking = true
        notice = nil
        state = .deletingAccount

        do {
            try await authService.requestAccountDeletion()
            apply(.signedOut)
            hasStartedSync = false
        } catch {
            apply(previousRoute)
            notice = .deleteAccountFailed
        }

        isWorking = false
    }

    private func refreshAuthRoute() async {
        do {
            let session = try await authService.restoreSession()
            apply(AuthRoute(session: session))
        } catch {
            apply(.signedOut)
            notice = .sessionLoadFailed
        }
    }

    private func performAuthAction(
        failureNotice: RootNotice,
        action: () async throws -> Void
    ) async {
        guard !isWorking else {
            return
        }

        isWorking = true
        notice = nil

        do {
            try await action()
        } catch {
            notice = failureNotice
        }

        isWorking = false
    }

    private func apply(_ route: AuthRoute) {
        authRoute = route
        state = route.appState
    }

    private func startSyncIfNeeded() async {
        guard !hasStartedSync else {
            return
        }

        switch authRoute {
        case .limitedAuthenticated:
            await syncCoordinator.start()
            hasStartedSync = true
        case .signedOut, .onboarding:
            return
        }
    }
}
