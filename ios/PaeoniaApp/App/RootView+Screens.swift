import SwiftUI

/// The routed screens. Each `AppState` maps to one screen, except that a saved
/// partner code shows the join screen in place of the paywall or pairing.
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
        // Saving or forgetting a partner's code swaps screens without a state change.
        .animation(PaeoniaMotion.meaningfulMoment, value: framedScreen)
    }

    private var framedScreen: RootFramedScreen? {
        // The partner joined while the inviter was answering or drawing. The invite
        // screen stays until that closes, so the task isn't cut off.
        if viewModel.state == .paired, inviterTaskIsOpen {
            return .pairing
        }

        // A partner's code takes the place of the paywall and the invite screen.
        if PendingJoinInviteFlowResolver().shouldPresentInviteAcceptance(
            for: viewModel.state,
            pendingInviteCode: pendingJoinInviteCode
        ) {
            return .join
        }

        return switch viewModel.state {
        case .onboarding:
            .onboarding
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
        case .accountClosed:
            .accountClosed
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
                // Someone joining a partner's code confirms the date after joining.
                asksStartDate: pendingJoinInviteCode == nil,
                startDateQueue: featureDependencies.firstDayStartedOnQueue,
                onCompleteOnboarding: completeOnboarding,
                onSignOut: signOut,
                onDeleteAccount: deleteAccount
            )
        case .paywall:
            paywallScreen
        case .pairing:
            pairingScreen
        case .join:
            joinScreen
        case .relationshipEnded:
            RelationshipEndedNoticeView(
                isWorking: viewModel.isWorking,
                onAcknowledge: acknowledgeRelationshipEnded
            )
        case .accountClosed:
            AccountClosedView(
                isWorking: viewModel.isWorking,
                onSignOut: signOut,
                onDeleteAccount: deleteAccount
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
            audience: paywallAudience,
            isCheckingAccess: viewModel.route.isResolvingAccess,
            onPurchaseConfirmed: subscriptionChanged,
            onSubmitInviteCode: submitJoinCode,
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

    /// A subscribed user who is not paired yet.
    private var pairingScreen: some View {
        PairingInviteView(
            session: viewModel.currentSession,
            viewModel: featureDependencies.pairingInviteViewModel,
            firstDayModel: featureDependencies.inviterFirstDayModel,
            onSubmitJoinCode: submitJoinCode,
            onRefreshAccess: refreshPairing
        )
        .environment(\.inviterTaskOpenChanged, InviterTaskOpenAction { isOpen in
            inviterTaskIsOpen = isOpen
            // A drawing sent after the partner joined was saved as waiting. The
            // couple's widget sync sends it.
            if !isOpen {
                syncWidgetIfPaired(viewModel.state)
            }
        })
    }

    /// Someone with a partner's code from a link, the welcome screen, the paywall
    /// or the invite screen. Without a subscription of their own it replaces the
    /// paywall.
    private var joinScreen: some View {
        PairingJoinView(
            viewModel: pairingJoinViewModel,
            code: pendingJoinInviteCode,
            currentUserID: viewModel.currentSession?.id,
            replacesPaywall: viewModel.state == .limitedAuthenticated,
            onSubmitCode: submitJoinCode,
            onAccepted: inviteAccepted,
            onForgetCode: { pendingJoinInviteCode = nil },
            onSignOut: signOut,
            onDeleteAccount: deleteAccount
        )
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
            } else if viewModel.isFirstDayPresented {
                postPairingSequence
                    .transition(.opacity)
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
        .animation(pairedScreenAnimation, value: viewModel.isFirstDayPresented)
        // Starts loading the first day steps while the celebration plays.
        .onChange(of: postPairingContext, initial: true) { _, context in
            if let context {
                postPairingFlow.prepare(context)
            }
        }
        // Signed out or unpaired. Signing back in to the same pair starts over.
        .onDisappear {
            postPairingFlow.reset()
        }
    }

    /// Who the first day sequence is for, while the celebration or the sequence is up.
    private var postPairingContext: PostPairingContext? {
        guard viewModel.isPairingCelebrationPresented || viewModel.isFirstDayPresented,
              let pairID = viewModel.currentPairID,
              let currentUserID = viewModel.currentSession.flatMap({ UUID(uuidString: $0.id) }),
              let partnerUserID = viewModel.currentPartnerUserID,
              let coupleID = viewModel.currentActiveCoupleID
        else {
            return nil
        }
        return PostPairingContext(
            pairID: pairID,
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            coupleID: coupleID
        )
    }

    private var postPairingSequence: some View {
        PostPairingFlowView(
            model: postPairingFlow,
            partnerName: partnerNameForCopy,
            currentDisplayName: viewModel.currentSession?.displayName,
            startedOn: viewModel.currentRelationshipStartedOn,
            acceptedInvite: viewModel.currentRelationshipAcceptedInvite,
            syncAfterLocalChange: { await viewModel.syncAfterLocalChange() },
            onFinish: finishFirstDay
        )
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
            shareLocation: { await shareLocation() },
            sentSomethingToPartner: offerPrimersAfterSharing,
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
            // The prefetched gift turns the last button into the way to it.
            dismissTitle: postPairingFlow.gift == nil
                ? .pairingCelebrationGetStartedButton
                : .onboardingFirstDayGiftButton(partnerNameForCopy),
            onIntroComplete: {
                viewModel.consumePairingCelebration()
            },
            onDismiss: {
                dismissPairingCelebration()
            }
        )
        .analyticsScreen("pairing_celebration")
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space16)
        // Same column as the onboarding and pairing screens just before it.
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var pairedScreenAnimation: Animation? {
        reduceMotion ? nil : PaeoniaMotion.pairedScreenTransition
    }
}
