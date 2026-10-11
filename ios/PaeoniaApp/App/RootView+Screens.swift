import SwiftUI

/// The routed screens. Each `AppState` maps to exactly one screen.
extension RootView {
    /// The routed surfaces crossfade into each other (sign-in → profile setup →
    /// paywall) instead of swapping in one frame, so moving through the flow reads
    /// as one continuous journey. A fade only, so Reduce Motion needs no branch.
    var routedRootContent: some View {
        ZStack {
            Group {
                // One branch for every paywall route, so saving a pending invite
                // code doesn't swap in a new PaywallView and drop its confirm alert.
                if showsPaywallScreen {
                    paywallScreen
                } else {
                    routedContentForCurrentState
                }
            }
            .transition(.opacity)
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: viewModel.state)
    }

    private var showsPaywallScreen: Bool {
        switch viewModel.state {
        case .limitedAuthenticated, .pairedPaywalled:
            true
        case .entitlementLost, .entitlementRestored:
            // The access resolver does not produce these today. The paywall is
            // the screen that can recover access if it ever does.
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var routedContentForCurrentState: some View {
        switch viewModel.state {
        case .launching:
            // Only seen under the cold-launch intro.
            Color.paeoniaBackgroundPrimary
                .ignoresSafeArea()
        case .unauthenticated:
            welcomeScreen
        case .onboarding:
            onboardingScaffold
        case .unpaired, .invitePending:
            pairingScaffold
        case .paired:
            pairedScaffold
        case .relationshipEndedNotice:
            relationshipEndedScaffold
        case .deletingAccount,
             .limitedAuthenticated,
             .pairedPaywalled,
             .entitlementLost,
             .entitlementRestored:
            deletingAccountScaffold
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
    private var pairingScaffold: some View {
        brandedScaffold {
            PairingInviteView(
                session: viewModel.currentSession,
                viewModel: featureDependencies.pairingInviteViewModel,
                pendingJoinCode: pendingJoinCodeForPairing,
                onClearPendingJoinCode: { pendingJoinInviteCode = nil },
                onInviteAccepted: inviteAccepted,
                onRefreshAccess: refreshPairing
            )
        }
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

    private var relationshipEndedScaffold: some View {
        brandedScaffold {
            RelationshipEndedNoticeView(
                isWorking: viewModel.isWorking,
                onAcknowledge: acknowledgeRelationshipEnded
            )
        }
    }

    private var onboardingScaffold: some View {
        brandedScaffold {
            AuthOnboardingView(
                session: viewModel.currentSession,
                isWorking: viewModel.isWorking,
                onCompleteOnboarding: completeOnboarding,
                onSignOut: signOut,
                onDeleteAccount: deleteAccount
            )
        }
    }

    private var deletingAccountScaffold: some View {
        brandedScaffold {
            AuthDeletingAccountView()
        }
    }

    /// The pre-pairing screens share one frame: the brand lockup on top and the
    /// screen's own content filling the rest.
    private func brandedScaffold(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                PaeoniaBrandLockup(
                    wordmarkSize: 36,
                    taglineSize: 17,
                    taglineColor: .paeoniaTextSecondary
                )
                .frame(maxWidth: .infinity)
                .screenEntrance(order: 0)

                content()
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
