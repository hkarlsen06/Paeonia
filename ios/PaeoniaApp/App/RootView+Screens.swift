import SwiftUI

/// The routed screens. Each `AppState` maps to exactly one screen.
extension RootView {
    /// The routed surfaces crossfade into each other instead of swapping in one
    /// frame. The screens between sign-in and the paired app share one frame, so
    /// from profile setup through the paywall to pairing the logo stays in place
    /// and only the content under it changes. A fade only, so Reduce Motion needs
    /// no branch.
    var routedRootContent: some View {
        ZStack {
            if let framedScreen {
                RootBrandedFrame {
                    framedContent(framedScreen)
                        .id(framedScreen)
                        .transition(.opacity)
                }
                .transition(.opacity)
            } else {
                unframedContent
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: viewModel.state)
    }

    private var framedScreen: RootFramedScreen? {
        switch viewModel.state {
        case .onboarding:
            .onboarding
        // One screen for every paywall state, so saving a pending invite code
        // doesn't swap in a new PaywallView and drop its confirm alert.
        case .limitedAuthenticated, .pairedPaywalled:
            .paywall
        case .entitlementLost, .entitlementRestored:
            // The access resolver does not produce these today. The paywall is
            // the screen that can recover access if it ever does.
            .paywall
        case .unpaired, .invitePending:
            .pairing
        case .relationshipEndedNotice:
            .relationshipEnded
        case .deletingAccount:
            .deletingAccount
        case .launching, .unauthenticated, .paired:
            nil
        }
    }

    @ViewBuilder
    private func framedContent(_ screen: RootFramedScreen) -> some View {
        switch screen {
        case .onboarding:
            AuthOnboardingView(
                session: viewModel.currentSession,
                isWorking: viewModel.isWorking,
                onCompleteOnboarding: completeOnboarding,
                onSignOut: signOut,
                onDeleteAccount: deleteAccount
            )
        case .paywall:
            paywallScreen
        case .pairing:
            pairingScreen
        case .relationshipEnded:
            RelationshipEndedNoticeView(
                isWorking: viewModel.isWorking,
                onAcknowledge: acknowledgeRelationshipEnded
            )
        case .deletingAccount:
            AuthDeletingAccountView()
        }
    }

    @ViewBuilder
    private var unframedContent: some View {
        switch viewModel.state {
        case .unauthenticated:
            welcomeScreen
        case .paired:
            pairedScaffold
        default:
            // Only seen under the cold-launch intro.
            Color.paeoniaBackgroundPrimary
                .ignoresSafeArea()
        }
    }

    private var welcomeScreen: some View {
        WelcomeView(
            isWorking: viewModel.isWorking,
            signingInWith: viewModel.signingInWith,
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
            isCheckingAccess: viewModel.route.isResolvingAccess,
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

    /// A subscribed user who is not paired yet. A partner's code from a link or
    /// the welcome screen is joined right here instead of on the paywall.
    private var pairingScreen: some View {
        PairingInviteView(
            session: viewModel.currentSession,
            viewModel: featureDependencies.pairingInviteViewModel,
            pendingJoinCode: pendingJoinCodeForPairing,
            onClearPendingJoinCode: { pendingJoinInviteCode = nil },
            onInviteAccepted: inviteAccepted,
            onRefreshAccess: refreshPairing
        )
    }

    private var pendingJoinCodeForPairing: String? {
        guard PendingJoinInviteFlowResolver().shouldPresentInviteAcceptance(
            for: viewModel.state,
            pendingInviteCode: pendingJoinInviteCode
        ) else {
            return nil
        }

        return pendingJoinInviteCode
    }

    private var pairedScaffold: some View {
        ZStack {
            if viewModel.isPairingCelebrationPresented {
                pairingCelebration
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
            } else {
                mainTabs
                    .transition(
                        .asymmetric(
                            insertion: reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .animation(pairedScreenAnimation, value: viewModel.isPairingCelebrationPresented)
    }

    private var mainTabs: some View {
        MainTabView(
            identity: mainTabIdentity,
            locationMapState: locationViewModel.mapState,
            locationViewModel: locationViewModel,
            selection: mainTabSelection,
            widgetDrawingPresented: widgetDrawingPresented,
            deepLink: $deepLink,
            actions: mainTabActions,
            dependencies: featureDependencies
        )
    }

    private var mainTabIdentity: MainTabIdentity {
        MainTabIdentity(
            currentUserID: viewModel.currentSession.flatMap { UUID(uuidString: $0.id) },
            currentDisplayName: viewModel.currentSession?.displayName,
            currentProfilePhotoAssetID: viewModel.currentProfilePhotoAssetID,
            currentCustomProfilePhotoAssetID: viewModel.currentCustomProfilePhotoAssetID,
            currentProviderProfilePhotoAssetID: viewModel.currentProviderProfilePhotoAssetID,
            currentAuthProvider: viewModel.currentSession?.provider,
            partnerUserID: viewModel.currentPartnerUserID,
            partnerDisplayName: viewModel.currentPartnerDisplayName,
            partnerProfilePhotoAssetID: viewModel.currentPartnerProfilePhotoAssetID,
            coupleID: viewModel.currentActiveCoupleID,
            relationshipStartedOn: viewModel.currentRelationshipStartedOn
        )
    }

    private var mainTabActions: MainTabActions {
        MainTabActions(
            openWidgetDrawing: { viewModel.openWidgetDrawing() },
            refreshHome: { await refreshHomeSurfacesFromPull() },
            refreshDailyChallenge: { await viewModel.refreshFromHomePull() },
            syncAfterLocalChange: { await viewModel.syncAfterLocalChange() },
            leftRelationship: refreshPairing,
            logOut: signOut,
            isLoggingOut: viewModel.isWorking,
            deleteAccount: deleteAccount,
            updateProfile: { displayName, profilePhotoUpdate in
                await viewModel.updateCurrentProfile(
                    displayName: displayName,
                    profilePhotoUpdate: profilePhotoUpdate
                )
            },
            purchasesRestored: {
                await viewModel.refreshAfterSubscriptionChange()
            }
        )
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

    var pairedScreenAnimation: Animation? {
        reduceMotion ? nil : PaeoniaMotion.pairedScreenTransition
    }
}
