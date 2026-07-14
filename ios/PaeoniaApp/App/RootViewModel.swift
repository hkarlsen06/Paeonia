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
    case relationshipEndedAcknowledgeFailed
}

enum RootPresentedDestination: Equatable {
    case widgetDrawing
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

    private let syncService: any PaeoniaSyncing
    private let privacyLifecycle: RootPrivacyLifecycle
    private let authService: any AuthServicing
    private let accessRouteService: (any AccessRouteServicing)?
    private let accessSnapshotStore: (any AccessSyncSnapshotPersisting)?
    private let inviteStore: any PairingInviteStoring
    private let pairingCelebrationStore: any PairingCelebrationStoring

    private var route: RootRoute = .launching
    private(set) var isWorking = false
    private(set) var notice: RootNotice?
    /// Set when Paeonia data deletion succeeded but Apple could not revoke the
    /// Sign in with Apple authorization automatically.
    private(set) var requiresManualAppleRevocation = false
    private(set) var presentedDestination: RootPresentedDestination?
    /// The selected paired tab. Owned here (rather than in the tab view) so that
    /// navigation intent can move the user to the right tab and present its
    /// destination as one atomic change. See [openWidgetDrawing].
    private(set) var selectedMainTab: MainTab = .home
    private var hasStartedSync = false
    private var configuredSyncSession: SyncSession?
    private var accessResolutionGeneration = 0
    @ObservationIgnored private var inFlightAccessPrivacyPurge: (
        id: UUID,
        task: Task<LocalPrivacyPurgeResult, Never>
    )?
    private var opensWidgetDrawingWhenPaired = false
    private var shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives = false

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

    var currentPartnerUserID: UUID? {
        route.accessResolution?.partnerUserID
    }

    var currentActiveCoupleID: UUID? {
        route.accessResolution?.activeCoupleID
    }

    var currentRelationshipStartedOn: String? {
        route.accessResolution?.relationshipStartedOn
    }

    var currentProfilePhotoAssetID: UUID? {
        currentSession?.profilePhotoAssetID
    }

    var currentCustomProfilePhotoAssetID: UUID? {
        currentSession?.customProfilePhotoAssetID
    }

    var currentProviderProfilePhotoAssetID: UUID? {
        currentSession?.providerProfilePhotoAssetID
    }

    var currentPartnerProfilePhotoAssetID: UUID? {
        route.accessResolution?.partnerProfilePhotoAssetID
    }

    /// True while the one-time celebration interstitial is presented above the
    /// paired state. The regular paired screen is shown once this is false.
    private(set) var isPairingCelebrationPresented = false

    /// True when the currently presented celebration should play its intro. This
    /// is cleared once the celebration has claimed it, while the interstitial
    /// itself stays visible until the user dismisses it.
    private(set) var pendingPairingCelebration = false

    init(
        syncService: (any PaeoniaSyncing)? = nil,
        authService: (any AuthServicing)? = nil,
        accessRouteService: (any AccessRouteServicing)? = nil,
        accessSnapshotStore: (any AccessSyncSnapshotPersisting)? = nil,
        inviteStore: (any PairingInviteStoring)? = nil,
        pairingCelebrationStore: (any PairingCelebrationStoring)? = nil
    ) {
        let resolvedSyncService = syncService ?? PaeoniaSyncService()
        self.syncService = resolvedSyncService
        self.privacyLifecycle = RootPrivacyLifecycle(syncService: resolvedSyncService)
        self.authService = authService ?? AuthServiceFactory.makeDefault()
        self.accessRouteService = accessRouteService ?? (try? SupabaseAccessRouteService.live())
        self.accessSnapshotStore = accessSnapshotStore ?? Self.makeDefaultAccessSnapshotStore()
        self.inviteStore = inviteStore ?? UserDefaultsPairingInviteStore.shared
        self.pairingCelebrationStore = pairingCelebrationStore ?? UserDefaultsPairingCelebrationStore.shared
    }

    private static func makeDefaultAccessSnapshotStore() -> (any AccessSyncSnapshotPersisting)? {
        guard let localStore = PaeoniaLocalStore.shared else {
            return nil
        }

        return SwiftDataAccessSyncSnapshotRepository(container: localStore.container)
    }

    func start(deferringSyncUntilLaunchCompletes: Bool = false) async {
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
        pendingPairingCelebration = false
    }

    func dismissPairingCelebration() {
        pendingPairingCelebration = false
        isPairingCelebrationPresented = false
        markCurrentPairingCelebrationSeen()
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
            clearPairingCelebrationPresentation()
            clearPendingWidgetDrawingOpen()
            route = .signedOut
            await syncService.resetForUserChange()
            PushRegistrationFingerprintStore.resetAll()
            hasStartedSync = false
            configuredSyncSession = nil
        }
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async {
        guard !isWorking else {
            return
        }

        let previousRoute = route
        isWorking = true
        notice = nil
        requiresManualAppleRevocation = false
        invalidateAccessResolution()
        clearPairingCelebrationPresentation()
        clearPendingWidgetDrawingOpen()
        route = .deletingAccount(previousRoute.session)

        do {
            let outcome = try await authService.requestAccountDeletion(
                appleAuthorizationCode: appleAuthorizationCode
            )
            requiresManualAppleRevocation = outcome == .manualAppleRevocationRequired
            invalidateAccessResolution()
            clearPairingCelebrationPresentation()
            route = .signedOut
            await syncService.resetForUserChange()
            PushRegistrationFingerprintStore.resetAll()
            hasStartedSync = false
            configuredSyncSession = nil
        } catch {
            if case .access = previousRoute {
                isPairingCelebrationPresented = false
            }
            route = previousRoute
            notice = .deleteAccountFailed
        }

        isWorking = false
    }

    func dismissManualAppleRevocation() {
        requiresManualAppleRevocation = false
    }

    func refreshAfterSubscriptionChange() async {
        await refreshAuthRoute()
        await startSyncIfNeeded()
    }

    /// Saves the paired user's canonical profile while preserving the resolved
    /// relationship route. The updated session is committed immediately so all
    /// current-user labels and avatars refresh together, then a sync pass pulls
    /// the latest partner/access snapshot without making the save depend on it.
    func updateCurrentProfile(
        displayName: String,
        profilePhotoUpdate: AuthProfilePhotoUpdate
    ) async -> Bool {
        guard !isWorking,
              state == .paired,
              case let .access(_, resolution) = route
        else {
            return false
        }

        isWorking = true
        notice = nil
        defer { isWorking = false }

        do {
            let session = try await authService.updateProfile(
                displayName: displayName,
                profilePhotoUpdate: profilePhotoUpdate
            )
            route = .access(session, resolution)
            await startSyncIfNeeded()
            _ = await syncService.runOnce(reason: .localChange)
            await resolveAccessRoute(for: session)
            return true
        } catch {
            logAuthError(error, notice: nil)
            return false
        }
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

    func refreshAfterPairingChange() async {
        await refreshAuthRoute()
        await startSyncIfNeeded()
    }

    /// Confirms the user has read the relationship-ended notice. Marks the notice
    /// seen on the backend so it does not reappear after the next sync, then
    /// re-resolves access to land on the user's real next state (usually unpaired).
    /// On failure the notice stays put and a banner explains what happened.
    func acknowledgeRelationshipEnded() async {
        guard !isWorking,
              case let .access(session, resolution) = route,
              resolution.route == .relationshipEndedNotice,
              let coupleID = resolution.activeCoupleID
        else {
            return
        }

        isWorking = true
        notice = nil

        do {
            try await accessRouteService?.markRelationshipEndedNoticeSeen(coupleID: coupleID)
            await resolveAccessRoute(for: session)
            await startSyncIfNeeded()
        } catch {
            notice = .relationshipEndedAcknowledgeFailed
        }

        isWorking = false
    }

    func refreshAfterForegroundActivation() async {
        if await privacyLifecycle.retryPendingOnForeground(),
           let session = currentSession {
            privacyLifecycle.cancelRecovery()
            await resolveAccessRoute(for: session)
        }
        await startSyncIfNeeded()

        guard hasStartedSync, currentSession != nil else {
            return
        }

        _ = await syncService.runOnce(reason: .foreground)
        await applySyncedAccessSnapshotIfAvailable()
    }

    func syncAfterLocalLocationChange() async {
        await syncAfterLocalChange()
    }

    /// Flushes pending local changes (e.g. a queued media answer) to the backend now,
    /// starting sync first if it hasn't begun.
    func syncAfterLocalChange() async {
        await startSyncIfNeeded()

        guard hasStartedSync, currentSession != nil else {
            return
        }

        _ = await syncService.runOnce(reason: .localChange)
    }

    /// Pull-to-refresh on Home. The widget sync is triggered alongside this from
    /// the view (see `RootView`).
    func refreshFromHomePull() async {
        await startSyncIfNeeded()

        guard hasStartedSync, currentSession != nil else {
            return
        }

        _ = await syncService.runOnce(reason: .manualRefresh)
        await applySyncedAccessSnapshotIfAvailable()
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
            clearPairingCelebrationPresentation()
            clearPendingWidgetDrawingOpen()
            route = .signedOut
        case let .onboarding(session):
            invalidateAccessResolution()
            clearPairingCelebrationPresentation()
            clearPendingWidgetDrawingOpen()
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
            let fallbackResolution = await fallbackAccessResolution(
                for: session,
                previous: previousAccessResolution
            )
            await finishAccessResolution(
                generation,
                resolution: fallbackResolution,
                for: session,
                previous: previousAccessResolution
            )
            return
        }

        do {
            let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil
            let accessResolution = try await accessRouteService.resolveAccess(hasPendingInvite: hasPendingInvite)
            await finishAccessResolution(
                generation,
                resolution: accessResolution,
                for: session,
                previous: previousAccessResolution
            )
        } catch {
            let fallbackResolution = await fallbackAccessResolution(
                for: session,
                previous: previousAccessResolution
            )
            await finishAccessResolution(
                generation,
                resolution: fallbackResolution,
                for: session,
                previous: previousAccessResolution
            )
        }
    }

    /// Commits a resolved access route and, in the same step, decides whether the
    /// one-time pairing celebration should be presented above the paired screen.
    private func applyAccessResolution(
        _ resolution: AccessRouteResolution,
        for session: AuthSession,
        previous: AccessRouteResolution?
    ) {
        let shouldCelebrate = pendingPairingCelebration
            || Self.isFreshLink(from: previous?.route, to: resolution.route)
        applyPairingCelebrationPresentation(for: resolution, shouldCelebrate: shouldCelebrate)
        route = .access(session, resolution)
        presentPendingWidgetDrawingIfNeeded(for: resolution.route)
    }

    private func showAcceptedInviteCelebration(for session: AuthSession) {
        pendingPairingCelebration = true
        isPairingCelebrationPresented = true
        shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives = false
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

    private func applySyncedAccessSnapshotIfAvailable() async {
        guard let session = currentSession else {
            return
        }

        let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil
        guard let resolution = await syncedAccessResolution(
            for: session,
            hasPendingInvite: hasPendingInvite
        ) else {
            return
        }

        let generation = accessResolutionGeneration
        let previousAccessResolution = route.accessResolution
        await finishAccessResolution(
            generation,
            resolution: resolution,
            for: session,
            previous: previousAccessResolution
        )
        await startSyncIfNeeded()
    }

    private func syncedAccessResolution(
        for session: AuthSession,
        hasPendingInvite: Bool
    ) async -> AccessRouteResolution? {
        guard let userID = UUID(uuidString: session.id),
              let accessSnapshotStore
        else {
            return nil
        }

        guard let snapshot = try? await accessSnapshotStore.load(ownerUserID: userID) else {
            return nil
        }

        let routeSnapshot = AccessRouteSnapshot(
            userEntitlement: snapshot.userEntitlement,
            coupleEntitlement: snapshot.coupleEntitlement,
            relationshipState: snapshot.relationshipState,
            hasPendingInvite: hasPendingInvite
        )

        return AccessRouteResolution(
            route: AccessRouteResolver().route(for: routeSnapshot),
            snapshot: routeSnapshot
        )
    }

    private func fallbackAccessResolution(
        for session: AuthSession,
        previous: AccessRouteResolution?
    ) async -> AccessRouteResolution {
        let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil

        if let syncedResolution = await syncedAccessResolution(
            for: session,
            hasPendingInvite: hasPendingInvite
        ) {
            return syncedResolution
        }

        if let previous {
            return previous
        }

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

    private func applyPairingCelebrationPresentation(
        for resolution: AccessRouteResolution,
        shouldCelebrate: Bool
    ) {
        guard resolution.route == .paired else {
            clearPairingCelebrationPresentation()
            dismissPresentedDestination()
            clearPendingWidgetDrawingOpen()
            return
        }

        if shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives {
            if markPairingCelebrationSeen(for: resolution) {
                shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives = false
            }
            pendingPairingCelebration = false
            isPairingCelebrationPresented = false
            return
        }

        if isPairingCelebrationPresented {
            return
        }

        let hasSeenCelebration = hasSeenPairingCelebration(for: resolution)
        pendingPairingCelebration = shouldCelebrate && !hasSeenCelebration
        isPairingCelebrationPresented = !hasSeenCelebration
    }

    private func markCurrentPairingCelebrationSeen() {
        guard let accessResolution = route.accessResolution,
              markPairingCelebrationSeen(for: accessResolution) else {
            shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives = true
            return
        }

        shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives = false
    }

    @discardableResult
    private func markPairingCelebrationSeen(for resolution: AccessRouteResolution) -> Bool {
        guard let pairID = resolution.pairingCelebrationPairID else {
            return false
        }

        pairingCelebrationStore.markCelebrationSeen(forPairID: pairID)
        return true
    }

    private func hasSeenPairingCelebration(for resolution: AccessRouteResolution) -> Bool {
        guard let pairID = resolution.pairingCelebrationPairID else {
            return false
        }

        return pairingCelebrationStore.hasSeenCelebration(forPairID: pairID)
    }

    private func clearPairingCelebrationPresentation() {
        pendingPairingCelebration = false
        isPairingCelebrationPresented = false
        shouldMarkPresentedPairingCelebrationSeenWhenKeyArrives = false
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

    private func beginAccessResolution() -> Int {
        accessResolutionGeneration += 1
        return accessResolutionGeneration
    }

    private func invalidateAccessResolution() {
        accessResolutionGeneration += 1
    }

    private func finishAccessResolution(
        _ generation: Int,
        resolution: AccessRouteResolution,
        for session: AuthSession,
        previous: AccessRouteResolution?
    ) async {
        // Every access commit waits for an older privacy purge, including a
        // newer `.paired` result. This prevents a stale ended/paywalled result
        // from continuing to clear caches after the new route becomes visible.
        if let pendingPurge = inFlightAccessPrivacyPurge {
            _ = await pendingPurge.task.value
        }

        guard generation == accessResolutionGeneration else {
            return
        }

        await purgePrivateRelationshipDataIfNeeded(
            for: resolution,
            ownerSession: session,
            previous: previous
        )

        // Privacy cleanup is asynchronous. A sign-out, user change, or newer
        // access resolution may have won while it ran, so never let the older
        // result restore a stale route afterwards.
        guard generation == accessResolutionGeneration else {
            return
        }

        if resolution.route == .paired {
            guard await privacyLifecycle.retryPending() else {
                schedulePrivacyPurgeRecovery(for: session)
                return
            }
        }

        applyAccessResolution(resolution, for: session, previous: previous)
    }

    private func schedulePrivacyPurgeRecovery(for session: AuthSession) {
        privacyLifecycle.scheduleRecovery { [weak self] in
            guard let self, self.currentSession?.id == session.id else {
                return
            }
            await self.resolveAccessRoute(for: session)
            await self.startSyncIfNeeded()
        }
    }

    private func purgePrivateRelationshipDataIfNeeded(
        for resolution: AccessRouteResolution,
        ownerSession: AuthSession,
        previous: AccessRouteResolution?
    ) async {
        guard let ownerUserID = UUID(uuidString: ownerSession.id) else {
            return
        }

        let permanently: Bool
        switch resolution.route {
        case .pairedPaywalled:
            // Entitlement can return. Hide downloaded relationship surfaces,
            // but keep canonical local drafts, memories, and pending writes.
            permanently = false
        case .relationshipEndedNotice:
            permanently = true
        case .limitedAuthenticated, .unpaired, .invitePending:
            if let relationshipState = resolution.snapshot.relationshipState {
                guard Self.isKnownEndedRelationship(relationshipState) else {
                    return
                }
            } else {
                // After retention removes the ended relationship row, the
                // current snapshot is intentionally empty. The prior in-memory
                // or persisted snapshot is the only cold-launch proof that this
                // is access loss rather than a person who has never paired.
                guard await hadPriorRelationship(
                    ownerUserID: ownerUserID,
                    previous: previous
                ) else {
                    return
                }
            }
            permanently = true
        case .paired:
            return
        }

        let purgeID = UUID()
        let purgeTask = Task {
            await syncService.purgeRelationshipAccess(
                ownerUserID: ownerUserID,
                permanently: permanently
            )
        }
        inFlightAccessPrivacyPurge = (purgeID, purgeTask)
        let purgeResult = await purgeTask.value
        privacyLifecycle.record(purgeResult)
        if inFlightAccessPrivacyPurge?.id == purgeID {
            inFlightAccessPrivacyPurge = nil
        }
    }

    private func hadPriorRelationship(
        ownerUserID: UUID,
        previous: AccessRouteResolution?
    ) async -> Bool {
        if previous?.snapshot.relationshipState != nil {
            return true
        }

        guard let accessSnapshotStore else {
            return false
        }

        do {
            return try await accessSnapshotStore
                .load(ownerUserID: ownerUserID)?
                .relationshipState != nil
        } catch {
            // An unavailable history store is not proof of relationship loss.
            // Keep local pending work rather than deleting it speculatively.
            return false
        }
    }

    private static func isKnownEndedRelationship(
        _ relationshipState: SupabaseRelationshipState
    ) -> Bool {
        if relationshipState.endedAt != nil {
            return true
        }

        return switch (relationshipState.relationshipStatus, relationshipState.memberStatus) {
        case (.ended, _),
             (.deleted, _),
             (_, .left),
             (_, .endedNoticePending),
             (_, .endedNoticeSeen):
            true
        default:
            false
        }
    }

    private func startSyncIfNeeded() async {
        guard !privacyLifecycle.hasPendingRetry else {
            return
        }

        switch authRoute {
        case .signedOut, .onboarding:
            return
        case let .limitedAuthenticated(session):
            guard let userID = UUID(uuidString: session.id) else {
                return
            }

            let syncSession = SyncSession(
                userID: userID,
                activeCoupleID: syncActiveCoupleID,
                relationshipCoupleID: currentActiveCoupleID
            )
            if configuredSyncSession != syncSession {
                await syncService.configure(session: syncSession)
                configuredSyncSession = syncSession
            }

            if !hasStartedSync {
                await syncService.start()
                hasStartedSync = true
            }
        }
    }

    private var syncActiveCoupleID: UUID? {
        guard route.accessResolution?.route == .paired else {
            return nil
        }

        return currentActiveCoupleID
    }
}
