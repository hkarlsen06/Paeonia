import Foundation
import SwiftUI
import UIKit

struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var bannerCenter = PaeoniaBannerCenter()
    @Binding private var widgetDeepLink: PaeoniaWidgetDeepLink?
    @Binding private var pendingJoinInviteCode: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let appleSignInProvider: any AppleSignInProviding
    private let googleSignInProvider: any GoogleSignInProviding
    private let widgetCanvasService: any WidgetCanvasManaging
    private let widgetCanvasSync: any WidgetCanvasSyncing
    private let pushAuthorization: any PushAuthorizationProviding

    @MainActor
    init(
        widgetDeepLink: Binding<PaeoniaWidgetDeepLink?> = .constant(nil),
        pendingJoinInviteCode: Binding<String?> = .constant(nil),
        viewModel: RootViewModel? = nil,
        appleSignInProvider: (any AppleSignInProviding)? = nil,
        googleSignInProvider: (any GoogleSignInProviding)? = nil,
        widgetCanvasService: (any WidgetCanvasManaging)? = nil,
        widgetCanvasSync: (any WidgetCanvasSyncing)? = nil,
        pushAuthorization: (any PushAuthorizationProviding)? = nil
    ) {
        _viewModel = State(initialValue: viewModel ?? RootViewModel())
        _widgetDeepLink = widgetDeepLink
        _pendingJoinInviteCode = pendingJoinInviteCode
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInService()
        self.googleSignInProvider = googleSignInProvider ?? GoogleSignInService()
        self.widgetCanvasService = widgetCanvasService ?? WidgetCanvasService.shared
        self.widgetCanvasSync = widgetCanvasSync ?? WidgetCanvasSyncServiceFactory.makeDefault()
        self.pushAuthorization = pushAuthorization ?? PushAuthorizationService()
    }

    var body: some View {
        rootContent
            .environment(bannerCenter)
            .task {
                await viewModel.start()
            }
            .preferredColorScheme(.dark)
            // Handle widget deep links from an async task (fires on appear and
            // whenever the link changes) so navigation state is never mutated
            // synchronously during a view update.
            .task(id: widgetDeepLink) {
                handleWidgetDeepLink(widgetDeepLink)
            }
            .onChange(of: viewModel.notice) { _, notice in
                showBanner(for: notice)
            }
            .onChange(of: viewModel.state) { _, state in
                clearWidgetIfNeeded(for: state)
                syncWidgetIfPaired(state)
                requestPushAuthorizationIfPaired(state)
            }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncWidgetIfPaired(viewModel.state)
                Task {
                    await viewModel.refreshAfterForegroundActivation()
                }
            }
        }
            .onChange(of: viewModel.currentSession?.id) { _, sessionID in
                // Once signed in, get an APNs token so the backend can send the
                // silent push that wakes us to sync a partner's drawing.
                if sessionID != nil {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            .paeoniaTopBanner(bannerCenter)
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
                    currentDisplayName: viewModel.currentSession?.displayName,
                    currentProfilePhotoAssetID: viewModel.currentProfilePhotoAssetID,
                    partnerDisplayName: viewModel.currentPartnerDisplayName,
                    partnerProfilePhotoAssetID: viewModel.currentPartnerProfilePhotoAssetID,
                    authorName: viewModel.currentSession?.displayName,
                    selection: mainTabSelection,
                    widgetDrawingPresented: widgetDrawingPresented,
                    onOpenWidgetDrawing: { viewModel.openWidgetDrawing() }
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

    /// Keeps private drawing content off the Home Screen the moment the app
    /// leaves the paired state (sign out, account deletion, lost access, ended
    /// relationship). Never fires for `.launching`, so a paired user's saved
    /// drawing survives across launches.
    private func clearWidgetIfNeeded(for state: AppState) {
        guard state != .paired, state != .launching else {
            return
        }

        Task {
            await widgetCanvasService.clearForPrivacy()
        }
    }

    /// Pulls the partner's latest drawing (and our own latest) into the widget
    /// and in-app canvas whenever we're paired and the app comes forward.
    private func syncWidgetIfPaired(_ state: AppState) {
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
        Task {
            await widgetCanvasSync.sync(identity: identity)
        }
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
}

#Preview {
    RootView()
}
