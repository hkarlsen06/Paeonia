import Foundation
import SwiftUI
import UIKit

struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var locationViewModel: LocationMapViewModel
    @State private var bannerCenter = PaeoniaBannerCenter()
    @State private var isLaunchExperienceActive = true
    @State private var launchContentRevealed = false
    @State private var isPushPermissionPrimerPresented = false
    @State private var isPushPermissionPrimerEvaluationInFlight = false
    @Binding private var deepLink: PaeoniaDeepLink?
    @Binding private var pendingJoinInviteCode: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let appleSignInProvider: any AppleSignInProviding
    private let googleSignInProvider: any GoogleSignInProviding
    private let widgetCanvasService: any WidgetCanvasManaging
    private let widgetCanvasSync: any WidgetCanvasSyncing
    private let pushAuthorization: any PushAuthorizationProviding
    private let pushPermissionPrimerStore: any PushPermissionPrimerPersisting
    private let widgetPushRegistration: any WidgetPushRegistering
    private let partnerAvatarSharing: (any PartnerAvatarSharing)?
    private let featureDependencies: RootFeatureDependencies
    private let allowsSystemIntegrations: Bool
    /// Lets the first screen's entrance animation settle before sync, widget, avatar,
    /// and APNs warm-up begin. None of this work is required to choose the route.
    private static let postLaunchWorkDelay: Duration = .milliseconds(700)

    @MainActor
    init(
        deepLink: Binding<PaeoniaDeepLink?> = .constant(nil),
        pendingJoinInviteCode: Binding<String?> = .constant(nil),
        viewModel: RootViewModel? = nil,
        locationViewModel: LocationMapViewModel? = nil,
        appleSignInProvider: (any AppleSignInProviding)? = nil,
        googleSignInProvider: (any GoogleSignInProviding)? = nil,
        widgetCanvasService: (any WidgetCanvasManaging)? = nil,
        widgetCanvasSync: (any WidgetCanvasSyncing)? = nil,
        pushAuthorization: (any PushAuthorizationProviding)? = nil,
        pushPermissionPrimerStore: (any PushPermissionPrimerPersisting)? = nil,
        widgetPushRegistration: (any WidgetPushRegistering)? = nil,
        partnerAvatarSharing: (any PartnerAvatarSharing)? = nil,
        featureDependencies: RootFeatureDependencies = RootFeatureDependencies(),
        allowsSystemIntegrations: Bool = true
    ) {
        _viewModel = State(initialValue: viewModel ?? RootViewModel())
        _locationViewModel = State(initialValue: locationViewModel ?? LocationMapViewModel())
        _deepLink = deepLink
        _pendingJoinInviteCode = pendingJoinInviteCode
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInService()
        self.googleSignInProvider = googleSignInProvider ?? GoogleSignInService.shared
        self.widgetCanvasService = widgetCanvasService ?? WidgetCanvasService.shared
        self.widgetCanvasSync = widgetCanvasSync ?? WidgetCanvasSyncServiceFactory.makeDefault()
        self.pushAuthorization = pushAuthorization ?? PushAuthorizationService()
        self.pushPermissionPrimerStore = pushPermissionPrimerStore ?? UserDefaultsPushPermissionPrimerStore()
        self.widgetPushRegistration = widgetPushRegistration ?? WidgetPushRegistrationServiceFactory.makeDefault()
        self.partnerAvatarSharing = partnerAvatarSharing ?? PartnerAvatarSharingServiceFactory.makeDefault()
        self.featureDependencies = featureDependencies
        self.allowsSystemIntegrations = allowsSystemIntegrations
    }

    var body: some View {
        rootContent
            .environment(bannerCenter)
            .task {
                locationViewModel.setLocalChangeSyncHandler {
                    await viewModel.syncAfterLocalLocationChange()
                }
                await viewModel.start(deferringSyncUntilLaunchCompletes: true)
            }
            .task(id: isLaunchExperienceActive) {
                guard !isLaunchExperienceActive else { return }

                do {
                    try await Task.sleep(for: Self.postLaunchWorkDelay)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                registerForRemoteNotificationsIfSignedIn(viewModel.currentSession?.id)
                await viewModel.finishDeferredLaunchStartup()
                await performWidgetSyncIfPaired(viewModel.state)
            }
            .preferredColorScheme(.dark)
            // Handle deep links from an async task (fires on appear and whenever
            // the link changes) so navigation state is never mutated
            // synchronously during a view update.
            .task(id: deepLink) {
                handleDeepLink(deepLink)
            }
            .task(id: locationIdentity) {
                await locationViewModel.configure(identity: locationIdentity)
            }
            .onChange(of: viewModel.notice) { _, notice in
                showBanner(for: notice)
            }
            .onChange(of: locationViewModel.notice) { _, notice in
                showBanner(for: notice)
            }
            // A partner's widget update arrived while the app is open: the delegate
            // suppressed the system banner and relayed it here for the in-app one.
            .onChange(of: PaeoniaNotificationRouter.shared.pendingForegroundNotice) { _, notice in
                guard allowsSystemIntegrations else {
                    return
                }
                guard let notice else {
                    return
                }
                bannerCenter.show(
                    .info(
                        title: notice.title,
                        message: notice.message,
                        imageData: partnerAvatarData(),
                        isTappable: true
                    )
                )
                PaeoniaNotificationRouter.shared.consumeForegroundNotice()
            }
            .onChange(of: viewModel.state) { _, state in
                if !isLaunchExperienceActive {
                    syncWidgetIfPaired(state)
                }
                presentPushPermissionPrimerIfNeeded(for: state)
            }
            .onChange(of: viewModel.isPairingCelebrationPresented) { _, isPresented in
                if !isPresented {
                    presentPushPermissionPrimerIfNeeded(for: viewModel.state)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !isLaunchExperienceActive else {
                    return
                }
                // Re-arm APNs so a rotated token reaches registration; the
                // fingerprint gate drops the RPC when nothing changed.
                registerForRemoteNotificationsIfSignedIn(viewModel.currentSession?.id)
                // One ordered pass per activation instead of four racing tasks:
                // refresh our location, run a single foreground sync, reload the
                // map, then pull the partner's widget drawing.
                Task {
                    await locationViewModel.refreshOwnLocationIfSharingEnabled(source: .foregroundOpen)
                    await viewModel.refreshAfterForegroundActivation()
                    await locationViewModel.reload()
                    await performWidgetSyncIfPaired(viewModel.state)
                }
            }
            .onChange(of: viewModel.currentSession?.id, initial: true) { _, sessionID in
                // Once signed in, get an APNs token so the backend can send the
                // silent push that wakes us to sync a partner's drawing.
                if !isLaunchExperienceActive {
                    registerForRemoteNotificationsIfSignedIn(sessionID)
                }
            }
            .paeoniaTopBanner(bannerCenter) {
                // Tapping a partner-update notice opens the drawing screen, the
                // same destination the notification tap routes to.
                viewModel.openWidgetDrawing()
            }
            .alert(
                Text(.authDeleteAccountAppleManualTitle),
                isPresented: manualAppleRevocationBinding
            ) {
                Button {
                    viewModel.dismissManualAppleRevocation()
                    if let url = URL(string: "https://account.apple.com/") {
                        openURL(url)
                    }
                } label: {
                    Text(.authDeleteAccountAppleManualOpenButton)
                }

                Button(role: .cancel) {
                    viewModel.dismissManualAppleRevocation()
                } label: {
                    Text(.authDeleteAccountAppleManualDoneButton)
                }
            } message: {
                Text(.authDeleteAccountAppleManualMessage)
            }
            .sheet(isPresented: $isPushPermissionPrimerPresented) {
                PushPermissionPrimerView(
                    partnerName: pushPermissionPrimerPartnerName,
                    onEnable: enablePushNotifications,
                    onNotNow: dismissPushPermissionPrimer
                )
            }
    }

    private var manualAppleRevocationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.requiresManualAppleRevocation },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissManualAppleRevocation()
                }
            }
        )
    }

    private var widgetDrawingPresented: Binding<Bool> {
        Binding(
            get: {
                viewModel.presentedDestination == .widgetDrawing
            },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissPresentedDestination()
                }
            }
        )
    }

    private var mainTabSelection: Binding<MainTab> {
        Binding(
            get: { viewModel.selectedMainTab },
            set: { viewModel.selectMainTab($0) }
        )
    }

    private var rootContent: some View {
        ZStack {
            routedRootContent
                // The intro cues the surface to cascade its content in as it exits, and
                // the Home map's flame sweep waits until the intro is fully done so it
                // doesn't play hidden behind the overlay.
                .environment(\.launchContentRevealed, launchContentRevealed)
                .environment(\.launchIntroComplete, !isLaunchExperienceActive)
                .zIndex(0)

            if isLaunchExperienceActive {
                // The intro drives its own timeline and tells us when to cue the content
                // (`onRevealContent`) and when it has fully exited (`onFinished`), so the
                // overlay stays mounted past the moment `state` leaves `.launching`.
                LaunchExperienceView(
                    contentReady: !isLaunching,
                    onRevealContent: { launchContentRevealed = true },
                    onFinished: {
                        isLaunchExperienceActive = false
                        presentPushPermissionPrimerIfNeeded(for: viewModel.state)
                    }
                )
                .transition(.identity)
                .zIndex(1)
            }
        }
    }

    private var isLaunching: Bool {
        viewModel.state == .launching
    }

    /// The routed surfaces crossfade into each other (sign-in → profile setup →
    /// paywall) instead of swapping in one frame, so moving through the flow reads
    /// as one continuous journey. A fade only, so Reduce Motion needs no branch.
    private var routedRootContent: some View {
        ZStack {
            Group {
                if PendingJoinInviteFlowResolver().shouldPresentInviteAcceptance(
                    for: viewModel.state,
                    pendingInviteCode: pendingJoinInviteCode
                ) {
                    paywallScreen
                } else {
                    routedContentForCurrentState
                }
            }
            .transition(.opacity)
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: viewModel.state)
    }

    @ViewBuilder
    private var routedContentForCurrentState: some View {
        switch viewModel.state {
        case .launching:
            Color.paeoniaBackgroundPrimary
                .ignoresSafeArea()
        case .unauthenticated:
            welcomeScreen
        case .limitedAuthenticated, .pairedPaywalled, .entitlementLost:
            paywallScreen
        case .onboarding:
            onboardingScaffold
        case .unpaired, .invitePending:
            pairingScaffold
        case .paired:
            pairedScaffold
        case .relationshipEndedNotice:
            relationshipEndedScaffold
        default:
            scaffold
        }
    }

    private var welcomeScreen: some View {
        WelcomeView(
            isWorking: viewModel.isWorking,
            pendingInviteCode: pendingJoinInviteCode,
            onAppleSignIn: signInWithApple,
            onGoogleSignIn: signInWithGoogle,
            onSubmitInviteCode: captureInviteCode
        )
    }

    private var paywallScreen: some View {
        PaywallView(
            session: viewModel.currentSession,
            pendingInviteCode: $pendingJoinInviteCode,
            audience: paywallAudience,
            onPurchaseConfirmed: subscriptionChanged,
            onInviteAccepted: inviteAccepted,
            onSignOut: signOut,
            onUnpaired: refreshPairing,
            onDeleteAccount: deleteAccount,
            viewModel: featureDependencies.paywallViewModel,
            presentationOverride: featureDependencies.paywallPresentationOverride
        )
    }

    /// A paired-but-unentitled couple gets the paired paywall (clear partner
    /// context plus an unpair action); everyone else on the paywall is a signed-in
    /// user who is not paired yet.
    private var paywallAudience: PaywallAudience {
        switch viewModel.state {
        case .pairedPaywalled:
            .paired(partnerName: viewModel.currentPartnerDisplayName)
        default:
            .unpaired
        }
    }

    private var scaffold: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                    header
                    content
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.screenTopSpacing)
                .padding(.bottom, PaeoniaSpacing.space40)
            }
            .background(.paeoniaBackgroundPrimary)
        }
    }

    private var pairingScaffold: some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                header

                PairingInviteView(
                    session: viewModel.currentSession,
                    viewModel: featureDependencies.pairingInviteViewModel,
                    onRefreshAccess: refreshPairing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.paeoniaBackgroundPrimary)
        }
    }

    private var relationshipEndedScaffold: some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                header

                RelationshipEndedNoticeView(
                    isWorking: viewModel.isWorking,
                    onAcknowledge: acknowledgeRelationshipEnded
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.paeoniaBackgroundPrimary)
        }
    }

    private var onboardingScaffold: some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                header
                    .screenEntrance(order: 0)

                AuthOnboardingView(
                    session: viewModel.currentSession,
                    isWorking: viewModel.isWorking,
                    onCompleteOnboarding: completeOnboarding,
                    onSignOut: signOut,
                    onDeleteAccount: deleteAccount
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.paeoniaBackgroundPrimary)
        }
    }

    private var pairedScaffold: some View {
        ZStack {
            if viewModel.isPairingCelebrationPresented {
                pairingCelebration
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: pairedCelebrationRemovalTransition
                        )
                    )
            } else {
                MainTabView(
                    currentUserID: viewModel.currentSession.flatMap { UUID(uuidString: $0.id) },
                    currentDisplayName: viewModel.currentSession?.displayName,
                    currentProfilePhotoAssetID: viewModel.currentProfilePhotoAssetID,
                    currentCustomProfilePhotoAssetID: viewModel.currentCustomProfilePhotoAssetID,
                    currentProviderProfilePhotoAssetID: viewModel.currentProviderProfilePhotoAssetID,
                    currentAuthProvider: viewModel.currentSession?.provider,
                    partnerUserID: viewModel.currentPartnerUserID,
                    partnerDisplayName: viewModel.currentPartnerDisplayName,
                    partnerProfilePhotoAssetID: viewModel.currentPartnerProfilePhotoAssetID,
                    authorName: viewModel.currentSession?.displayName,
                    coupleID: viewModel.currentActiveCoupleID,
                    relationshipStartedOn: viewModel.currentRelationshipStartedOn,
                    locationMapState: locationViewModel.mapState,
                    locationViewModel: locationViewModel,
                    selection: mainTabSelection,
                    widgetDrawingPresented: widgetDrawingPresented,
                    deepLink: $deepLink,
                    onOpenWidgetDrawing: { viewModel.openWidgetDrawing() },
                    onHomeRefresh: { await refreshHomeSurfacesFromPull() },
                    onDailyChallengeRefresh: { await viewModel.refreshFromHomePull() },
                    onDailyChallengeLocalChange: { await viewModel.syncAfterLocalChange() },
                    onRelationshipStartedOnLocalChange: { await viewModel.syncAfterLocalChange() },
                    onMemoriesLocalChange: { await viewModel.syncAfterLocalChange() },
                    onLeftRelationship: refreshPairing,
                    onLogout: signOut,
                    onDeleteAccount: deleteAccount,
                    onUpdateProfile: { displayName, profilePhotoUpdate in
                        await viewModel.updateCurrentProfile(
                            displayName: displayName,
                            profilePhotoUpdate: profilePhotoUpdate
                        )
                    },
                    onPurchasesRestored: {
                        await viewModel.refreshAfterSubscriptionChange()
                    },
                    dailyChallengeViewModel: featureDependencies.dailyChallengeViewModel,
                    milestoneViewModel: featureDependencies.milestoneViewModel,
                    memoriesViewModel: featureDependencies.memoriesViewModel,
                    settingsViewModel: featureDependencies.settingsViewModel,
                    settingsPrivacyService: featureDependencies.settingsPrivacyService,
                    settingsPrivacyOperationProvider: featureDependencies.settingsPrivacyOperationProvider,
                    widgetDrawingViewModel: featureDependencies.widgetDrawingViewModel,
                    widgetHistoryViewModel: featureDependencies.widgetHistoryViewModel,
                    widgetHistoryThumbnailLoader: featureDependencies.widgetHistoryThumbnailLoader
                )
                .transition(
                    .asymmetric(
                        insertion: pairedHomeInsertionTransition,
                        removal: .opacity
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .animation(pairedScreenAnimation, value: viewModel.isPairingCelebrationPresented)
    }

    private var pairingCelebration: some View {
        PairingCelebrationView(
            currentDisplayName: viewModel.currentSession?.displayName,
            currentProfilePhotoAssetID: viewModel.currentProfilePhotoAssetID,
            partnerDisplayName: viewModel.currentPartnerDisplayName,
            partnerProfilePhotoAssetID: viewModel.currentPartnerProfilePhotoAssetID,
            playsIntro: viewModel.pendingPairingCelebration,
            onIntroComplete: {
                viewModel.consumePairingCelebration()
            },
            onDismiss: {
                dismissPairingCelebration()
            }
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pairedScreenAnimation: Animation? {
        reduceMotion ? nil : PaeoniaMotion.pairedScreenTransition
    }

    private var pairedCelebrationRemovalTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    private var pairedHomeInsertionTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var header: some View {
        PaeoniaBrandLockup(
            wordmarkSize: 36,
            taglineSize: 17,
            taglineColor: .paeoniaTextSecondary
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .launching:
            // Handled at the top level by `LaunchExperienceView`; never shown here.
            EmptyView()
        case .unauthenticated:
            // Handled at the top level by `welcomeScreen`; never shown here.
            EmptyView()
        case .onboarding:
            // Handled by `onboardingScaffold`; never shown here.
            EmptyView()
        case .limitedAuthenticated:
            // Handled at the top level by `paywallScreen`; never shown here.
            EmptyView()
        case .unpaired, .invitePending:
            // Handled by `pairingScaffold`; never shown here.
            EmptyView()
        case .deletingAccount:
            AuthDeletingAccountView()
        case .entitlementRestored:
            privateSpacePlaceholder
        case .paired:
            // Handled by `pairedScaffold`; never shown here.
            EmptyView()
        case .pairedPaywalled,
             .entitlementLost:
            AuthUnavailableRouteView()
        case .relationshipEndedNotice:
            // Handled by `relationshipEndedScaffold`; never shown here.
            EmptyView()
        }
    }

    private var privateSpacePlaceholder: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .rootEmptyTitle,
                message: .rootEmptyMessage,
                systemImage: "heart.circle.fill"
            )
        }
    }

    private func signInWithApple() {
        Task {
            await viewModel.signInWithApple(using: appleSignInProvider)
        }
    }

    private func signInWithGoogle() {
        Task {
            await viewModel.signInWithGoogle(using: googleSignInProvider)
        }
    }

    /// Stashes an invite code a joining partner entered before signing in. Once they
    /// sign in, the paywall reads this pending code so they join their partner instead
    /// of paying. The binding owner persists production changes so this view remains
    /// safe to host with an in-memory binding in local flows and previews.
    private func captureInviteCode(_ code: String) {
        pendingJoinInviteCode = code
    }

    private func completeOnboarding(displayName: String, profilePhotoData: Data?) {
        Task {
            await viewModel.completeOnboarding(
                displayName: displayName,
                timeZoneID: TimeZone.current.identifier,
                profilePhotoData: profilePhotoData
            )
        }
    }

    private func signOut() {
        Task {
            await viewModel.signOut()
            finishDepartingUserCleanup()
        }
    }

    private func deleteAccount() {
        Task {
            let authorizationCode: String?
            if viewModel.currentSession?.provider == .apple {
                let credential = try? await appleSignInProvider.signIn()
                authorizationCode = credential?.authorizationCode
            } else {
                authorizationCode = nil
            }

            // If Apple re-authentication is cancelled or unavailable, deletion
            // still proceeds and the server records Apple's documented manual
            // revocation fallback.
            await viewModel.deleteAccount(appleAuthorizationCode: authorizationCode)
            finishDepartingUserCleanup()
        }
    }

    /// Provider identity and invite codes must not carry into the next app
    /// account. Keep both intact when an account action fails, and clear them
    /// only after the current user has actually departed.
    private func finishDepartingUserCleanup() {
        guard viewModel.state == .unauthenticated else {
            return
        }

        googleSignInProvider.signOut()
        pendingJoinInviteCode = nil
    }

    private func subscriptionChanged() {
        Task {
            await viewModel.refreshAfterSubscriptionChange()
        }
    }

    private func inviteAccepted() {
        Task {
            await viewModel.refreshAfterInviteAccepted()
        }
    }

    private func refreshPairing() {
        Task {
            await viewModel.refreshAfterPairingChange()
        }
    }

    private func acknowledgeRelationshipEnded() {
        Task {
            await viewModel.acknowledgeRelationshipEnded()
        }
    }

    private func dismissPairingCelebration() {
        withAnimation(pairedScreenAnimation) {
            viewModel.dismissPairingCelebration()
        }
    }

    /// Reads the partner avatar the app stages in the shared App Group (the same
    /// image the notification service extension uses) so the in-app notice can
    /// show the partner's face instead of a generic icon.
    private func partnerAvatarData() -> Data? {
        guard let url = PaeoniaAppGroup.containerURL?
            .appendingPathComponent(PaeoniaAppGroup.communicationPartnerAvatarPath)
        else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    @MainActor
    private func handleDeepLink(_ deepLink: PaeoniaDeepLink?) {
        guard let deepLink else {
            return
        }

        switch deepLink {
        case .widgetDrawing:
            viewModel.openWidgetDrawing()
            self.deepLink = nil
        case .dailyReveal, .dailyToday:
            switch viewModel.state {
            case .paired, .launching:
                viewModel.selectMainTab(.questions)
            default:
                self.deepLink = nil
            }
        case .streak:
            if viewModel.state == .paired || viewModel.state == .launching {
                viewModel.selectMainTab(.home)
            }
            self.deepLink = nil
        case .subscription:
            openURL(PaeoniaDeepLink.appStoreSubscriptionsURL)
            self.deepLink = nil
        }
    }

    /// Pulls the partner's latest drawing (and our own latest) into the widget
    /// and in-app canvas whenever we're paired and the app comes forward.
    private func syncWidgetIfPaired(_ state: AppState) {
        Task { await performWidgetSyncIfPaired(state) }
    }

    /// Awaitable core of the widget sync, so pull-to-refresh can keep its spinner
    /// up until the partner's drawing and avatar are staged.
    private func performWidgetSyncIfPaired(_ state: AppState) async {
        guard allowsSystemIntegrations, state == .paired else {
            return
        }

        let identity = WidgetSyncIdentity(
            currentUserID: viewModel.currentSession.flatMap { UUID(uuidString: $0.id) },
            currentDisplayName: viewModel.currentSession?.displayName,
            partnerDisplayName: viewModel.currentPartnerDisplayName
        )
        // Persist so a silent-push-triggered background sync can label the
        // drawing with the right nickname even when no view is alive.
        WidgetSyncIdentityStore.shared.save(identity)
        await widgetCanvasSync.sync(identity: identity)
        await WidgetCenterReloader().reloadWidget()
        // Stage the partner's avatar so the alert can render it as a
        // communication notification while the app is in the background.
        await partnerAvatarSharing?.cachePartnerAvatar(assetID: viewModel.currentPartnerProfilePhotoAssetID)
    }

    private func registerForRemoteNotificationsIfSignedIn(_ sessionID: String?) {
        guard allowsSystemIntegrations, sessionID != nil else {
            return
        }

        UIApplication.shared.registerForRemoteNotifications()
        Task {
            await widgetPushRegistration.registerCurrentWidgetPushToken()
        }
    }

    /// Pull-to-refresh on Home after the Daily Challenge refresh has run: refreshes
    /// shared local surfaces and widget sync without delaying the challenge rollover.
    private func refreshHomeSurfacesFromPull() async {
        await locationViewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        await performWidgetSyncIfPaired(viewModel.state)
        await locationViewModel.reload()
    }

    /// Offers one calm, persisted explanation after pairing, once both the cold
    /// launch and pairing celebration are out of the way. The system dialog is
    /// only requested after the user explicitly continues from this primer.
    private func presentPushPermissionPrimerIfNeeded(for state: AppState) {
        guard state == .paired,
              !isLaunchExperienceActive,
              !viewModel.isPairingCelebrationPresented,
              !isPushPermissionPrimerPresented,
              !isPushPermissionPrimerEvaluationInFlight,
              !pushPermissionPrimerStore.hasResponded()
        else {
            return
        }

        isPushPermissionPrimerEvaluationInFlight = true
        Task { @MainActor in
            let isNotDetermined = await pushAuthorization.isNotDetermined()
            isPushPermissionPrimerEvaluationInFlight = false

            guard viewModel.state == .paired,
                  !isLaunchExperienceActive,
                  !viewModel.isPairingCelebrationPresented,
                  !pushPermissionPrimerStore.hasResponded()
            else {
                return
            }

            if isNotDetermined {
                isPushPermissionPrimerPresented = true
            } else {
                // A prior system choice makes the primer irrelevant. Persist
                // that settled state so later paired transitions stay quiet.
                pushPermissionPrimerStore.markResponded()
            }
        }
    }

    private var pushPermissionPrimerPartnerName: String {
        viewModel.currentPartnerDisplayName?.trimmedNonEmpty
            ?? String(localized: .pairingCelebrationPartnerName)
    }

    private func enablePushNotifications() {
        isPushPermissionPrimerPresented = false
        Task { @MainActor in
            let didSettleAuthorization = await pushAuthorization.requestAuthorizationIfNeeded()
            // Persist only after the call has reached and settled the system
            // authorization flow. If the app is terminated before then, the
            // primer remains eligible on the next launch instead of disappearing
            // forever while iOS is still `.notDetermined`.
            if didSettleAuthorization {
                pushPermissionPrimerStore.markResponded()
            }
        }
    }

    private func dismissPushPermissionPrimer() {
        pushPermissionPrimerStore.markResponded()
        isPushPermissionPrimerPresented = false
    }

    private func showBanner(for notice: RootNotice?) {
        guard let notice else {
            return
        }

        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        viewModel.dismissNotice()
    }

    private func showBanner(for notice: LocationMapViewModel.Notice?) {
        guard let notice else {
            return
        }

        let partnerName = viewModel.currentPartnerDisplayName?.trimmedNonEmpty
            ?? String(localized: .pairingCelebrationPartnerName)
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message(partnerName: partnerName))
            )
        )
        locationViewModel.dismissNotice()
    }

    private var locationIdentity: LocationIdentity {
        LocationIdentity(
            currentUserID: viewModel.currentSession.flatMap { UUID(uuidString: $0.id) },
            coupleID: viewModel.currentActiveCoupleID
        )
    }
}

#Preview {
    RootView()
}
