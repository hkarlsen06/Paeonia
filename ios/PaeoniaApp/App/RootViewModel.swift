import AuthenticationServices
import Foundation
import Observation
#if DEBUG
import OSLog
#endif

enum RootNotice: Equatable {
    case sessionLoadFailed
    case signInFailed
    case onboardingFailed
    case signOutFailed
    case deleteAccountFailed
}

@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class RootViewModel {
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Auth"
    )
    #endif

    private enum RootRoute: Equatable {
        case launching
        case signedOut
        case onboarding(AuthSession)
        case resolvingAccess(AuthSession, previous: AccessRouteResolution?)
        case access(AuthSession, AccessRouteResolution)
        case deletingAccount(AuthSession?)

        var appState: AppState {
            switch self {
            case .launching:
                .launching
            case .signedOut:
                .unauthenticated
            case .onboarding:
                .onboarding
            case let .resolvingAccess(_, previous):
                previous?.route.appState ?? .launching
            case let .access(_, accessResolution):
                accessResolution.route.appState
            case .deletingAccount:
                .deletingAccount
            }
        }

        var authRoute: AuthRoute {
            switch self {
            case .launching, .signedOut:
                .signedOut
            case let .onboarding(session):
                .onboarding(session)
            case let .resolvingAccess(session, _),
                 let .access(session, _),
                 let .deletingAccount(.some(session)):
                .limitedAuthenticated(session)
            case .deletingAccount(nil):
                .signedOut
            }
        }

        var session: AuthSession? {
            authRoute.session
        }

        var accessResolution: AccessRouteResolution? {
            switch self {
            case let .resolvingAccess(_, previous):
                previous
            case let .access(_, accessResolution):
                accessResolution
            case .launching,
                 .signedOut,
                 .onboarding,
                 .deletingAccount:
                nil
            }
        }
    }

    private let syncCoordinator: any SyncCoordinating
    private let authService: any AuthServicing
    private let accessRouteService: (any AccessRouteServicing)?
    private let inviteStore: any PairingInviteStoring

    private var route: RootRoute = .launching
    private(set) var isWorking = false
    private(set) var notice: RootNotice?
    private var hasStartedSync = false
    private var accessResolutionGeneration = 0

    var state: AppState {
        route.appState
    }

    var authRoute: AuthRoute {
        route.authRoute
    }

    var currentSession: AuthSession? {
        route.session
    }

    var currentPartnerDisplayName: String? {
        route.accessResolution?.partnerDisplayName
    }

    var currentProfilePhotoAssetID: UUID? {
        currentSession?.profilePhotoAssetID
    }

    var currentPartnerProfilePhotoAssetID: UUID? {
        route.accessResolution?.partnerProfilePhotoAssetID
    }

    /// True when access has just resolved to `.paired` as the result of a fresh
    /// link, so the paired screen should play its celebration intro. Set together
    /// with the route change so the paired screen reads the right value the instant
    /// it appears, then cleared once the celebration has claimed it.
    private(set) var pendingPairingCelebration = false

    init(
        syncCoordinator: (any SyncCoordinating)? = nil,
        authService: (any AuthServicing)? = nil,
        accessRouteService: (any AccessRouteServicing)? = nil,
        inviteStore: (any PairingInviteStoring)? = nil
    ) {
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator()
        self.authService = authService ?? AuthServiceFactory.makeDefault()
        self.accessRouteService = accessRouteService ?? (try? SupabaseAccessRouteService.live())
        self.inviteStore = inviteStore ?? UserDefaultsPairingInviteStore.shared
    }

    func start() async {
        await refreshAuthRoute()
        await startSyncIfNeeded()
    }

    func signInWithApple(using appleSignInProvider: any AppleSignInProviding) async {
        await performAuthAction(failureNotice: .signInFailed) {
            let credential = try await appleSignInProvider.signIn()
            let session = try await authService.signInWithApple(credential)
            await apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signInWithGoogle(using googleSignInProvider: any GoogleSignInProviding) async {
        await performAuthAction(failureNotice: .signInFailed) {
            let credential = try await googleSignInProvider.signIn()
            let session = try await authService.signInWithGoogle(credential)
            await apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signInForDevelopment() async {
        await performAuthAction(failureNotice: .signInFailed) {
            let session = try await authService.signInForDevelopment()
            await apply(AuthRoute(session: session))
        }
    }

    /// Clears the current notice after it has been handed to the app banner.
    func dismissNotice() {
        notice = nil
    }

    /// Marks the pairing celebration as played so it does not run again on an
    /// ordinary return to the paired screen.
    func consumePairingCelebration() {
        pendingPairingCelebration = false
    }

    func completeOnboarding(
        displayName: String,
        timeZoneID: String,
        profilePhotoData: Data?
    ) async {
        await performAuthAction(failureNotice: .onboardingFailed) {
            let session = try await authService.completeOnboarding(
                displayName: displayName,
                timeZoneID: timeZoneID,
                profilePhotoData: profilePhotoData
            )
            await apply(AuthRoute(session: session))
            await startSyncIfNeeded()
        }
    }

    func signOut() async {
        await performAuthAction(failureNotice: .signOutFailed) {
            try await authService.signOut()
            invalidateAccessResolution()
            route = .signedOut
            hasStartedSync = false
        }
    }

    func deleteAccount() async {
        guard !isWorking else {
            return
        }

        let previousRoute = route
        isWorking = true
        notice = nil
        invalidateAccessResolution()
        route = .deletingAccount(previousRoute.session)

        do {
            try await authService.requestAccountDeletion()
            invalidateAccessResolution()
            route = .signedOut
            hasStartedSync = false
        } catch {
            route = previousRoute
            notice = .deleteAccountFailed
        }

        isWorking = false
    }

    func refreshAfterSubscriptionChange() async {
        await refreshAuthRoute()
        await startSyncIfNeeded()
    }

    func refreshAfterInviteAccepted() async {
        guard let session = currentSession else {
            await refreshAuthRoute()
            await startSyncIfNeeded()
            return
        }

        showAcceptedInviteCelebration(for: session)
        await resolveAccessRoute(for: session)
        await startSyncIfNeeded()
    }

    func refreshAfterPairingChange() async {
        await refreshAuthRoute()
        await startSyncIfNeeded()
    }

    private func refreshAuthRoute() async {
        do {
            let session = try await authService.restoreSession()
            await apply(AuthRoute(session: session))
        } catch {
            invalidateAccessResolution()
            route = .signedOut
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
        } catch where Self.isUserCancelledAuthError(error) {
            logAuthError(error, notice: nil)
        } catch {
            logAuthError(error, notice: failureNotice)
            notice = failureNotice
        }

        isWorking = false
    }

    private static func isUserCancelledAuthError(_ error: Error) -> Bool {
        if let googleError = error as? GoogleSignInServiceError,
           googleError == .userCancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }

    private func logAuthError(_ error: Error, notice: RootNotice?) {
        #if DEBUG
        let noticeDescription = notice.map { String(describing: $0) } ?? "none"
        let errorDescription = String(describing: error)
        logger.error(
            """
            Auth action failed; notice=\(noticeDescription, privacy: .public); \
            error=\(errorDescription, privacy: .public)
            """
        )
        #endif
    }

    private func apply(_ authRoute: AuthRoute) async {
        switch authRoute {
        case .signedOut:
            invalidateAccessResolution()
            route = .signedOut
        case let .onboarding(session):
            invalidateAccessResolution()
            route = .onboarding(session)
        case let .limitedAuthenticated(session):
            await resolveAccessRoute(for: session)
        }
    }

    private func resolveAccessRoute(for session: AuthSession) async {
        let generation = beginAccessResolution()
        let previousAccessResolution = route.accessResolution
        route = .resolvingAccess(session, previous: previousAccessResolution)

        guard let accessRouteService else {
            finishAccessResolution(generation) {
                applyAccessResolution(
                    fallbackAccessResolution(for: session),
                    for: session,
                    previous: previousAccessResolution
                )
            }
            return
        }

        do {
            let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil
            let accessResolution = try await accessRouteService.resolveAccess(hasPendingInvite: hasPendingInvite)
            finishAccessResolution(generation) {
                applyAccessResolution(accessResolution, for: session, previous: previousAccessResolution)
            }
        } catch {
            finishAccessResolution(generation) {
                applyAccessResolution(
                    previousAccessResolution ?? fallbackAccessResolution(for: session),
                    for: session,
                    previous: previousAccessResolution
                )
            }
        }
    }

    /// Commits a resolved access route and, in the same step, decides whether the
    /// paired screen should celebrate. Keeping both in one synchronous update means
    /// the paired screen reads the correct `pendingPairingCelebration` the instant
    /// it appears, avoiding a race where the intro is skipped.
    private func applyAccessResolution(
        _ resolution: AccessRouteResolution,
        for session: AuthSession,
        previous: AccessRouteResolution?
    ) {
        let shouldCelebrate = pendingPairingCelebration
            || Self.isFreshLink(from: previous?.route, to: resolution.route)
        pendingPairingCelebration = resolution.route == .paired
            && shouldCelebrate
        route = .access(session, resolution)
    }

    private func showAcceptedInviteCelebration(for session: AuthSession) {
        pendingPairingCelebration = true
        route = .access(
            session,
            Self.acceptedInviteOptimisticResolution(previous: route.accessResolution)
        )
    }

    /// A fresh link is a transition into `.paired` from a state where the couple
    /// was not yet fully linked (an ordinary app open that is already paired starts
    /// from no previous route and must not replay).
    private static func isFreshLink(from previous: AccessRoute?, to current: AccessRoute) -> Bool {
        guard current == .paired, let previous else {
            return false
        }

        switch previous {
        case .invitePending, .unpaired, .limitedAuthenticated, .pairedPaywalled:
            return true
        case .paired, .relationshipEndedNotice:
            return false
        }
    }

    private func fallbackAccessResolution(for session: AuthSession) -> AccessRouteResolution {
        let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil

        return AccessRouteResolution(
            route: hasPendingInvite ? .invitePending : .limitedAuthenticated,
            snapshot: AccessRouteSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: nil,
                hasPendingInvite: hasPendingInvite
            )
        )
    }

    private static func acceptedInviteOptimisticResolution(
        previous: AccessRouteResolution?
    ) -> AccessRouteResolution {
        AccessRouteResolution(
            route: .paired,
            snapshot: AccessRouteSnapshot(
                userEntitlement: previous?.snapshot.userEntitlement,
                coupleEntitlement: previous?.snapshot.coupleEntitlement,
                relationshipState: previous?.snapshot.relationshipState,
                hasPendingInvite: false
            )
        )
    }

    private func beginAccessResolution() -> Int {
        accessResolutionGeneration += 1
        return accessResolutionGeneration
    }

    private func invalidateAccessResolution() {
        accessResolutionGeneration += 1
    }

    private func finishAccessResolution(_ generation: Int, action: () -> Void) {
        guard generation == accessResolutionGeneration else {
            return
        }

        action()
    }

    private func startSyncIfNeeded() async {
        guard !hasStartedSync else {
            return
        }

        switch authRoute {
        case .signedOut, .onboarding:
            return
        case .limitedAuthenticated:
            await syncCoordinator.start()
            hasStartedSync = true
        }
    }
}
