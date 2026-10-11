import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// Root auth, access, and pairing state. Sign-in, sign-out, profile, and
/// deletion live in `RootViewModel+Account.swift`; access resolution and
/// privacy purges in `RootViewModel+AccessResolution.swift`; sync startup and
/// live access observation in `RootViewModel+Sync.swift`.
@MainActor
@Observable
final class RootViewModel {
    #if DEBUG
    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Auth"
    )
    #endif

    let syncService: any PaeoniaSyncing
    /// Live subscriptions follow the same session as `syncService`. Nil in tests
    /// and developer scenarios that inject their own sync service.
    let liveSync: (any LiveSyncCoordinating)?
    let privacyLifecycle: RootPrivacyLifecycle
    let authService: any AuthServicing
    let accessRouteService: (any AccessRouteServicing)?
    let accessSnapshotStore: (any AccessSyncSnapshotPersisting)?
    let inviteStore: any PairingInviteStoring
    let systemSideEffects: any RootSystemSideEffecting
    let deviceOwnerStore: any RootDeviceOwnerStoring
    /// Whether the auth provider still has an active session right now, read
    /// without a network call. `nil` from the closure means it is still
    /// loading. Without a closure (tests, development sign-in) nothing is watched.
    let authProviderSessionIsActive: (@MainActor () -> Bool?)?
    @ObservationIgnored private var authProviderWatch: Task<Void, Never>?
    /// How long a cold launch waits for the server before it shows the access
    /// state saved on this phone. The server result still replaces it later.
    let savedAccessGracePeriod: Duration

    /// Written only by this type and its extensions.
    var route: RootRoute = .launching {
        didSet {
            // A new pairing, account, or relationship always starts on Home.
            if route.appState != .paired {
                selectedMainTab = .home
            }
        }
    }
    /// Set only by this type and its extensions.
    var isWorking = false
    /// The provider of the sign-in that is running, so only its button shows a
    /// spinner. Cleared when that sign-in finishes, whatever the outcome.
    var signingInWith: AuthProvider?
    var notice: RootNotice?
    /// Set when Paeonia data deletion succeeded but Apple could not revoke the
    /// Sign in with Apple authorization automatically.
    var requiresManualAppleRevocation = false
    private(set) var presentedDestination: RootPresentedDestination?
    /// The selected paired tab. Owned here (rather than in the tab view) so that
    /// navigation intent can move the user to the right tab and present its
    /// destination as one atomic change. See [openWidgetDrawing].
    private(set) var selectedMainTab: MainTab = .home
    private var celebration: RootPairingCelebrationState
    /// Changes whenever a signed-in session ends on this phone. Async work that
    /// started under an older session compares it after each suspension and
    /// stops instead of acting for someone who already left.
    @ObservationIgnored var sessionEpoch = 0
    @ObservationIgnored var isSavingProfile = false
    @ObservationIgnored var hasStartedSync = false
    @ObservationIgnored var configuredSyncSession: SyncSession?
    @ObservationIgnored var accessResolutionGeneration = 0
    @ObservationIgnored var inFlightAccessPrivacyPurge: (
        id: UUID,
        task: Task<LocalPrivacyPurgeResult, Never>
    )?
    /// Re-routes when the live access feed writes a new snapshot. One task per
    /// signed-in user, started with sync and stopped on sign-out.
    @ObservationIgnored var accessObservation: (userID: UUID, task: Task<Void, Never>)?
    @ObservationIgnored private var opensWidgetDrawingWhenPaired = false

    /// True while the one-time celebration interstitial is presented above the
    /// paired state. The regular paired screen is shown once this is false.
    var isPairingCelebrationPresented: Bool {
        celebration.isPresented
    }

    /// True when the currently presented celebration should play its intro. This
    /// is cleared once the celebration has claimed it, while the interstitial
    /// itself stays visible until the user dismisses it.
    var pendingPairingCelebration: Bool {
        celebration.playsIntro
    }

    init(
        syncService: (any PaeoniaSyncing)? = nil,
        authService: (any AuthServicing)? = nil,
        accessRouteService: (any AccessRouteServicing)? = nil,
        accessSnapshotStore: (any AccessSyncSnapshotPersisting)? = nil,
        inviteStore: (any PairingInviteStoring)? = nil,
        pairingCelebrationStore: (any PairingCelebrationStoring)? = nil,
        systemSideEffects: (any RootSystemSideEffecting)? = nil,
        liveSync: (any LiveSyncCoordinating)? = nil,
        deviceOwnerStore: (any RootDeviceOwnerStoring)? = nil,
        authProviderSessionIsActive: (@MainActor () -> Bool?)? = nil,
        savedAccessGracePeriod: Duration = .seconds(1)
    ) {
        self.authProviderSessionIsActive = authProviderSessionIsActive
        let resolvedLiveSync = liveSync ?? (syncService == nil ? LiveSyncCoordinator.makeDefault() : nil)
        let resolvedSyncService = syncService ?? PaeoniaSyncService(liveSync: resolvedLiveSync)
        self.syncService = resolvedSyncService
        self.liveSync = resolvedLiveSync
        self.privacyLifecycle = RootPrivacyLifecycle(syncService: resolvedSyncService)
        self.authService = authService ?? AuthServiceFactory.makeDefault()
        self.accessRouteService = accessRouteService ?? (try? RemoteAccessRouteService.live())
        self.accessSnapshotStore = accessSnapshotStore ?? Self.makeDefaultAccessSnapshotStore()
        self.inviteStore = inviteStore ?? UserDefaultsPairingInviteStore.shared
        self.celebration = RootPairingCelebrationState(
            store: pairingCelebrationStore ?? UserDefaultsPairingCelebrationStore.shared
        )
        self.systemSideEffects = systemSideEffects ?? LiveRootSystemSideEffects()
        // Tests and developer scenarios inject a sync service and get a private
        // in-memory owner, so they never read or clear the real phone's marker.
        self.deviceOwnerStore = deviceOwnerStore
            ?? (syncService == nil ? UserDefaultsRootDeviceOwnerStore() : InMemoryRootDeviceOwnerStore())
        self.savedAccessGracePeriod = savedAccessGracePeriod
    }

    private static func makeDefaultAccessSnapshotStore() -> (any AccessSyncSnapshotPersisting)? {
        guard let localStore = PaeoniaLocalStore.shared else {
            return nil
        }

        return SwiftDataAccessSyncSnapshotRepository(container: localStore.container)
    }

    func start(deferringSyncUntilLaunchCompletes: Bool = false) async {
        watchAuthProviderSession()
        _ = await privacyLifecycle.retryPending()
        await refreshAuthRoute()
        if !deferringSyncUntilLaunchCompletes {
            await startSyncIfNeeded()
        }
    }

    /// Starts background sync after the cold-launch animation and first content
    /// entrance have finished. Auth/access resolution still happens before the
    /// reveal; only work that is not needed to choose the first screen is deferred.
    func finishDeferredLaunchStartup() async {
        await startSyncIfNeeded()
    }

    /// Follows the auth provider's session for the life of the app. When it
    /// ends on its own (expired, or ended on another device), the person goes
    /// back to sign-in instead of seeing every save fail.
    private func watchAuthProviderSession() {
        guard authProviderWatch == nil, let isActive = authProviderSessionIsActive else {
            return
        }

        let sessionStates = Observations { isActive() }
        authProviderWatch = Task { [weak self] in
            for await state in sessionStates where state == false {
                await self?.authSessionEnded()
            }
        }
    }

    /// Clears the current notice after it has been handed to the app banner.
    func dismissNotice() {
        notice = nil
    }

    /// Lets the tab bar write the user's manual tab selection back into the
    /// single source of truth.
    func selectMainTab(_ tab: MainTab) {
        selectedMainTab = tab
    }

    /// Opens the couple's widget drawing screen. The screen is a destination on
    /// the Home tab, so opening it always selects Home first; presenting it on a
    /// non-visible tab would otherwise leave it hidden behind whatever tab the
    /// user was last on.
    func openWidgetDrawing() {
        switch state {
        case .paired:
            presentWidgetDrawing()
        case .launching:
            opensWidgetDrawingWhenPaired = true
        default:
            opensWidgetDrawingWhenPaired = false
        }
    }

    func dismissPresentedDestination() {
        presentedDestination = nil
    }

    /// Selects the Home tab and presents the widget drawing destination as one
    /// atomic change. The single entry point keeps the "drawing lives on Home"
    /// rule in one place for every caller (direct tap and deferred deep link).
    private func presentWidgetDrawing() {
        selectedMainTab = .home
        presentedDestination = .widgetDrawing
    }

    /// Marks the pairing celebration intro as claimed so a SwiftUI view recreation
    /// cannot replay it while the interstitial is still on screen.
    func consumePairingCelebration() {
        celebration.consumeIntro()
    }

    func dismissPairingCelebration() {
        celebration.dismiss(currentResolution: route.accessResolution)
    }

    func refreshAfterInviteAccepted() async {
        guard let session = currentSession else {
            await refreshAuthRoute()
            await startSyncIfNeeded()
            return
        }

        guard await privacyLifecycle.retryPending() else {
            // A permanent owner-scoped purge from an earlier relationship must
            // finish before the new couple can write local content that the
            // delayed retry would otherwise remove.
            await resolveAccessRoute(for: session)
            await startSyncIfNeeded()
            schedulePrivacyPurgeRecovery(for: session)
            return
        }

        showAcceptedInviteCelebration(for: session)
        await resolveAccessRoute(for: session)
        await startSyncIfNeeded()
    }

    /// Restores the session at launch, or when no session is on screen.
    func refreshAuthRoute() async {
        do {
            let session = try await authService.restoreSession()
            await apply(AuthRoute(session: session))
        } catch {
            guard currentSession == nil else {
                // Never sign someone out because a check failed. The live
                // session watch notices a session that really ended.
                logAuthError(error, notice: nil)
                return
            }
            stopObservingAccessChanges()
            invalidateAccessResolution()
            route = .signedOut
            notice = .sessionLoadFailed
        }
    }

    func apply(_ authRoute: AuthRoute) async {
        switch authRoute {
        case .signedOut:
            if currentSession != nil {
                // The session ended without a sign-out from this phone.
                await endSession(purgingLocalData: false)
                notice = .sessionEnded
                return
            }
            stopObservingAccessChanges()
            invalidateAccessResolution()
            leaveRelationshipSurfaces()
            route = .signedOut
        case let .onboarding(session):
            await clearDataFromAnotherAccount(before: session)
            stopObservingAccessChanges()
            invalidateAccessResolution()
            leaveRelationshipSurfaces()
            route = .onboarding(session)
        case let .limitedAuthenticated(session):
            await clearDataFromAnotherAccount(before: session)
            await resolveAccessRoute(for: session)
        }
    }

    /// Commits a resolved access route and, in the same step, decides whether the
    /// one-time pairing celebration should be presented above the paired screen.
    func applyAccessResolution(
        _ resolution: AccessRouteResolution,
        for session: AuthSession,
        previous: AccessRouteResolution?
    ) {
        let shouldCelebrate = celebration.playsIntro
            || RootPairingCelebrationState.isFreshLink(from: previous?.route, to: resolution.route)
        celebration.update(for: resolution, shouldCelebrate: shouldCelebrate)
        if resolution.route != .paired {
            clearPendingWidgetDrawingOpen()
        }
        route = .access(session, resolution)
        presentPendingWidgetDrawingIfNeeded(for: resolution.route)
    }

    private func showAcceptedInviteCelebration(for session: AuthSession) {
        celebration.presentAcceptedInvite()
        route = .access(
            session,
            Self.acceptedInviteOptimisticResolution(previous: route.accessResolution)
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

    /// Clears everything that belongs to the paired surface: the celebration,
    /// an open drawing screen, and a drawing deep link waiting for launch.
    func leaveRelationshipSurfaces() {
        celebration.clear()
        clearPendingWidgetDrawingOpen()
    }

    private func presentPendingWidgetDrawingIfNeeded(for accessRoute: AccessRoute) {
        guard opensWidgetDrawingWhenPaired else {
            return
        }

        opensWidgetDrawingWhenPaired = false
        if accessRoute == .paired {
            presentWidgetDrawing()
        }
    }

    private func clearPendingWidgetDrawingOpen() {
        opensWidgetDrawingWhenPaired = false
        dismissPresentedDestination()
    }
}
