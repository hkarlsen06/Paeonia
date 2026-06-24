import SwiftUI

struct RootView: View {
    @State private var viewModel: RootViewModel
    private let appleSignInProvider: any AppleSignInProviding
    private let googleSignInProvider: any GoogleSignInProviding

    @MainActor
    init(
        viewModel: RootViewModel? = nil,
        appleSignInProvider: (any AppleSignInProviding)? = nil,
        googleSignInProvider: (any GoogleSignInProviding)? = nil
    ) {
        _viewModel = State(initialValue: viewModel ?? RootViewModel())
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInService()
        self.googleSignInProvider = googleSignInProvider ?? GoogleSignInService()
    }

    var body: some View {
        rootContent
            .task {
                await viewModel.start()
            }
            .preferredColorScheme(.dark)
            .paeoniaErrorAlert(alertContent) {
                viewModel.dismissNotice()
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch viewModel.state {
        case .unauthenticated:
            signInScreen
        case .limitedAuthenticated:
            paywallScreen
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
            onPurchaseConfirmed: subscriptionChanged,
            onAcceptInvite: viewModel.showInviteEntryPending,
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

    private var alertContent: PaeoniaAlertContent? {
        guard let notice = viewModel.notice else {
            return nil
        }

        return PaeoniaAlertContent(title: notice.title, message: notice.message)
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Text(.appTitle)
                .font(PaeoniaTypography.display)
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.appTagline)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)

            ViewThatFits {
                HStack(spacing: PaeoniaSpacing.space8) {
                    PaeoniaSyncStatusView(status: syncStatus)
                    stateLabel
                }

                VStack(spacing: PaeoniaSpacing.space8) {
                    PaeoniaSyncStatusView(status: syncStatus)
                    stateLabel
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .launching:
            AuthLaunchingView()
        case .unauthenticated:
            // Handled at the top level by `signInScreen`; never shown here.
            EmptyView()
        case .onboarding:
            AuthOnboardingView(
                session: viewModel.currentSession,
                isWorking: viewModel.isWorking,
                onCompleteOnboarding: completeOnboarding,
                onSignOut: signOut
            )
        case .limitedAuthenticated:
            // Handled at the top level by `paywallScreen`; never shown here.
            EmptyView()
        case .deletingAccount:
            AuthDeletingAccountView()
        case .reviewAccess,
             .unpaired,
             .invitePending,
             .paired,
             .pairedPaywalled,
             .entitlementLost,
             .entitlementRestored,
             .relationshipEndedNotice:
            AuthUnavailableRouteView()
        }
    }

    private var stateLabel: some View {
        Text(stateDescription)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(Capsule(style: .continuous))
    }

    private var syncStatus: PaeoniaSyncStatus {
        viewModel.state == .launching ? .syncing : .savedLocally
    }

    private var stateDescription: LocalizedStringResource {
        switch viewModel.state {
        case .launching:
            .appStateLaunching
        case .unauthenticated:
            .appStateUnauthenticated
        case .onboarding:
            .appStateOnboarding
        case .limitedAuthenticated:
            .appStateLimitedAuthenticated
        case .reviewAccess:
            .appStateReviewAccess
        case .unpaired:
            .appStateUnpaired
        case .invitePending:
            .appStateInvitePending
        case .paired:
            .appStatePaired
        case .pairedPaywalled:
            .appStatePairedPaywalled
        case .entitlementLost:
            .appStateEntitlementLost
        case .entitlementRestored:
            .appStateEntitlementRestored
        case .relationshipEndedNotice:
            .appStateRelationshipEndedNotice
        case .deletingAccount:
            .appStateDeletingAccount
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

    private func completeOnboarding(displayName: String) {
        Task {
            await viewModel.completeOnboarding(
                displayName: displayName,
                timeZoneID: TimeZone.current.identifier
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
}

private extension RootNotice {
    var title: LocalizedStringResource {
        switch self {
        case .sessionLoadFailed:
            .authNoticeSessionLoadFailedTitle
        case .signInFailed:
            .authNoticeSignInFailedTitle
        case .onboardingFailed:
            .authNoticeOnboardingFailedTitle
        case .signOutFailed:
            .authNoticeSignOutFailedTitle
        case .deleteAccountFailed:
            .authNoticeDeleteAccountFailedTitle
        case .inviteEntryPending:
            .authNoticeInviteEntryPendingTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .sessionLoadFailed:
            .authNoticeSessionLoadFailedMessage
        case .signInFailed:
            .authNoticeSignInFailedMessage
        case .onboardingFailed:
            .authNoticeOnboardingFailedMessage
        case .signOutFailed:
            .authNoticeSignOutFailedMessage
        case .deleteAccountFailed:
            .authNoticeDeleteAccountFailedMessage
        case .inviteEntryPending:
            .authNoticeInviteEntryPendingMessage
        }
    }
}

#Preview {
    RootView()
}
