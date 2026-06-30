import Foundation
import SwiftUI
import UIKit

struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var locationViewModel: LocationMapViewModel
    @State private var bannerCenter = PaeoniaBannerCenter()
    @State private var lastKnownAuthenticatedUserID: UUID?
    @Binding private var widgetDeepLink: PaeoniaWidgetDeepLink?
    @Binding private var pendingJoinInviteCode: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let appleSignInProvider: any AppleSignInProviding
    private let googleSignInProvider: any GoogleSignInProviding
    private let widgetCanvasService: any WidgetCanvasManaging
    private let widgetCanvasSync: any WidgetCanvasSyncing
    private let pushAuthorization: any PushAuthorizationProviding
    private let widgetPushRegistration: any WidgetPushRegistering
    private let partnerAvatarSharing: (any PartnerAvatarSharing)?

    @MainActor
    init(
        widgetDeepLink: Binding<PaeoniaWidgetDeepLink?> = .constant(nil),
        pendingJoinInviteCode: Binding<String?> = .constant(nil),
        viewModel: RootViewModel? = nil,
        locationViewModel: LocationMapViewModel? = nil,
        appleSignInProvider: (any AppleSignInProviding)? = nil,
        googleSignInProvider: (any GoogleSignInProviding)? = nil,
        widgetCanvasService: (any WidgetCanvasManaging)? = nil,
        widgetCanvasSync: (any WidgetCanvasSyncing)? = nil,
        pushAuthorization: (any PushAuthorizationProviding)? = nil,
        widgetPushRegistration: (any WidgetPushRegistering)? = nil,
        partnerAvatarSharing: (any PartnerAvatarSharing)? = nil
    ) {
        _viewModel = State(initialValue: viewModel ?? RootViewModel())
        _locationViewModel = State(initialValue: locationViewModel ?? LocationMapViewModel())
        _widgetDeepLink = widgetDeepLink
        _pendingJoinInviteCode = pendingJoinInviteCode
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInService()
        self.googleSignInProvider = googleSignInProvider ?? GoogleSignInService()
        self.widgetCanvasService = widgetCanvasService ?? WidgetCanvasService.shared
        self.widgetCanvasSync = widgetCanvasSync ?? WidgetCanvasSyncServiceFactory.makeDefault()
        self.pushAuthorization = pushAuthorization ?? PushAuthorizationService()
        self.widgetPushRegistration = widgetPushRegistration ?? WidgetPushRegistrationServiceFactory.makeDefault()
        self.partnerAvatarSharing = partnerAvatarSharing ?? PartnerAvatarSharingServiceFactory.makeDefault()
    }

    var body: some View {
        rootContent
            .environment(bannerCenter)
            .task {
                locationViewModel.setLocalChangeSyncHandler {
                    await viewModel.syncAfterLocalLocationChange()
                }
                await viewModel.start()
            }
            .preferredColorScheme(.dark)
            // Handle widget deep links from an async task (fires on appear and
            // whenever the link changes) so navigation state is never mutated
            // synchronously during a view update.
        .task(id: widgetDeepLink) {
            handleWidgetDeepLink(widgetDeepLink)
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
                clearWidgetIfNeeded(for: state)
                syncWidgetIfPaired(state)
                requestPushAuthorizationIfPaired(state)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    registerForRemoteNotificationsIfSignedIn(viewModel.currentSession?.id)
                    syncWidgetIfPaired(viewModel.state)
                    Task {
                        await locationViewModel.refreshOwnLocationIfSharingEnabled(source: .foregroundOpen)
                    await viewModel.refreshAfterForegroundActivation()
                    await locationViewModel.reload()
                }
            }
        }
        .onChange(of: viewModel.currentSession?.id, initial: true) { _, sessionID in
                // Once signed in, get an APNs token so the backend can send the
                // silent push that wakes us to sync a partner's drawing.
            rememberAuthenticatedUser(sessionID)
            registerForRemoteNotificationsIfSignedIn(sessionID)
        }
            .paeoniaTopBanner(bannerCenter) {
                // Tapping a partner-update notice opens the drawing screen, the
                // same destination the notification tap routes to.
                viewModel.openWidgetDrawing()
            }
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

    @ViewBuilder
    private var rootContent: some View {
        switch viewModel.state {
        case .launching:
            AuthLaunchingView()
        case .unauthenticated:
            signInScreen
        case .limitedAuthenticated, .pairedPaywalled, .entitlementLost:
            paywallScreen
        case .onboarding:
            onboardingScaffold
        case .unpaired, .invitePending:
            pairingScaffold
        case .paired:
            pairedScaffold
        default:
            scaffold
        }
    }

    private var signInScreen: some View {
        SignInView(
            isWorking: viewModel.isWorking,
            onAppleSignIn: signInWithApple,
            onGoogleSignIn: signInWithGoogle
        )
    }

    private var paywallScreen: some View {
        PaywallView(
            session: viewModel.currentSession,
            pendingInviteCode: $pendingJoinInviteCode,
            onPurchaseConfirmed: subscriptionChanged,
            onInviteAccepted: inviteAccepted,
            allowsInviteEntry: viewModel.state == .limitedAuthenticated,
            onSignOut: signOut,
            onDeleteAccount: deleteAccount
        )
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

    private var onboardingScaffold: some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                header

                AuthOnboardingView(
                    session: viewModel.currentSession,
                    isWorking: viewModel.isWorking,
                    onCompleteOnboarding: completeOnboarding,
                    onSignOut: signOut
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
                    partnerUserID: viewModel.currentPartnerUserID,
                    partnerDisplayName: viewModel.currentPartnerDisplayName,
                    partnerProfilePhotoAssetID: viewModel.currentPartnerProfilePhotoAssetID,
                    authorName: viewModel.currentSession?.displayName,
                    coupleID: viewModel.currentActiveCoupleID,
                    locationMapState: locationViewModel.mapState,
                    locationViewModel: locationViewModel,
                    selection: mainTabSelection,
                    widgetDrawingPresented: widgetDrawingPresented,
                    onOpenWidgetDrawing: { viewModel.openWidgetDrawing() },
                    onHomeRefresh: { await refreshHomeSurfacesFromPull() },
                    onDailyChallengeRefresh: { await viewModel.refreshFromHomePull() },
                    onDailyChallengeLocalChange: { await viewModel.syncAfterLocalChange() },
                    onMemoriesLocalChange: { await viewModel.syncAfterLocalChange() }
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
            // Handled at the top level by `AuthLaunchingView`; never shown here.
            EmptyView()
        case .unauthenticated:
            // Handled at the top level by `signInScreen`; never shown here.
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
        case .reviewAccess,
             .entitlementRestored:
            privateSpacePlaceholder
        case .paired:
            // Handled by `pairedScaffold`; never shown here.
            EmptyView()
        case .pairedPaywalled,
             .entitlementLost,
             .relationshipEndedNotice:
            AuthUnavailableRouteView()
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
        }
    }

    private func deleteAccount() {
        Task {
            await viewModel.deleteAccount()
        }
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

    private func handleWidgetDeepLink(_ deepLink: PaeoniaWidgetDeepLink?) {
        guard let deepLink else {
            return
        }

        switch deepLink {
        case .drawing:
            viewModel.openWidgetDrawing()
        }

        widgetDeepLink = nil
    }

    /// Keeps private content off the device the moment the app leaves the paired
    /// state (sign out, account deletion, lost access, ended relationship): the
    /// Home Screen drawing, the partner avatar, and any staged or cached daily-answer
    /// photos. Never fires for `.launching`, so a paired user's content survives
    /// across launches.
    private func clearWidgetIfNeeded(for state: AppState) {
        guard state != .paired, state != .launching else {
            return
        }

        let ownerUserID = viewModel.currentSession
            .flatMap { UUID(uuidString: $0.id) }
            ?? lastKnownAuthenticatedUserID

        Task {
            await widgetCanvasService.clearForPrivacy()
            await partnerAvatarSharing?.clear()
            FileDailyAnswerMediaDraftStore.live().clearAll()
            FileDailyChallengeSnapshotCache.live().clearAll()
            await (try? DailyAnswerMediaImageService.live())?.clearAll()
            await (try? MemoryMediaImageService.live())?.clearAll()
            if let ownerUserID {
                await MemoryDataServiceFactory.clearForPrivacy(ownerUserID: ownerUserID)
            }
        }
    }

    private func rememberAuthenticatedUser(_ sessionID: String?) {
        guard let sessionID, let userID = UUID(uuidString: sessionID) else {
            return
        }

        lastKnownAuthenticatedUserID = userID
    }

    /// Pulls the partner's latest drawing (and our own latest) into the widget
    /// and in-app canvas whenever we're paired and the app comes forward.
    private func syncWidgetIfPaired(_ state: AppState) {
        Task { await performWidgetSyncIfPaired(state) }
    }

    /// Awaitable core of the widget sync, so pull-to-refresh can keep its spinner
    /// up until the partner's drawing and avatar are staged.
    private func performWidgetSyncIfPaired(_ state: AppState) async {
        guard state == .paired else {
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
        guard sessionID != nil else {
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

    /// Asks for notification permission once the couple is paired (the first
    /// moment a partner can send a drawing). The request only prompts when the
    /// status is still undetermined, so repeated paired transitions are no-ops.
    private func requestPushAuthorizationIfPaired(_ state: AppState) {
        guard state == .paired else {
            return
        }

        Task {
            await pushAuthorization.requestAuthorizationIfNeeded()
        }
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
