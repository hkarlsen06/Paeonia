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

    var currentSession: AuthSession? {
        authRoute.session
    }

    init(
        syncCoordinator: (any SyncCoordinating)? = nil,
        authService: (any AuthServicing)? = nil
    ) {
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator()
        self.authService = authService ?? DevelopmentAuthService()
    }

    func start() async {
        await syncCoordinator.start()
        await refreshAuthRoute()
    }

    func signInForDevelopment() async {
        await performAuthAction(failureNotice: .signInFailed) {
            let session = try await authService.signInForDevelopment()
            apply(AuthRoute(session: session))
        }
    }

    func completeOnboarding() async {
        await performAuthAction(failureNotice: .onboardingFailed) {
            let session = try await authService.completeOnboarding()
            apply(AuthRoute(session: session))
        }
    }

    func signOut() async {
        await performAuthAction(failureNotice: .signOutFailed) {
            try await authService.signOut()
            apply(.signedOut)
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
            try await authService.deleteAccount()
            apply(.signedOut)
        } catch {
            apply(previousRoute)
            notice = .deleteAccountFailed
        }

        isWorking = false
    }

    private func refreshAuthRoute() async {
        do {
            let session = try await authService.currentSession()
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
}
