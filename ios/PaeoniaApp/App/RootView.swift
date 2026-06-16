import SwiftUI

struct RootView: View {
    @State private var viewModel: RootViewModel
    private let appleSignInProvider: any AppleSignInProviding

    @MainActor
    init(
        viewModel: RootViewModel? = nil,
        appleSignInProvider: (any AppleSignInProviding)? = nil
    ) {
        _viewModel = State(initialValue: viewModel ?? RootViewModel())
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInService()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                    header
                    noticeCard
                    content
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.screenTopSpacing)
                .padding(.bottom, PaeoniaSpacing.space40)
            }
            .background(.paeoniaBackgroundPrimary)
        }
        .task {
            await viewModel.start()
        }
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
    private var noticeCard: some View {
        if let notice = viewModel.notice {
            PaeoniaCard {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(notice.title)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(notice.message)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .launching:
            AuthLaunchingView()
        case .unauthenticated:
            AuthStartView(
                isWorking: viewModel.isWorking,
                onAppleSignIn: signInWithApple,
                onDevelopmentSignIn: signInForDevelopment
            )
        case .onboarding:
            AuthOnboardingView(
                session: viewModel.currentSession,
                isWorking: viewModel.isWorking,
                onCompleteOnboarding: completeOnboarding,
                onSignOut: signOut
            )
        case .limitedAuthenticated:
            AuthenticatedBaselineView(
                isWorking: viewModel.isWorking,
                onSignOut: signOut,
                onDeleteAccount: deleteAccount
            )
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

    private func signInForDevelopment() {
        Task {
            await viewModel.signInForDevelopment()
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
        }
    }
}

#Preview {
    RootView()
}
