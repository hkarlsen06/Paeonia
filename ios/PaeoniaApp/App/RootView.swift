import Foundation
import SwiftUI

struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var bannerCenter = PaeoniaBannerCenter()
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
            .environment(bannerCenter)
            .task {
                await viewModel.start()
            }
            .preferredColorScheme(.dark)
            .onChange(of: viewModel.notice) { _, notice in
                showBanner(for: notice)
            }
            .paeoniaTopBanner(bannerCenter)
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
        NavigationStack {
            PairingCelebrationView(
                currentDisplayName: viewModel.currentSession?.displayName,
                currentProfilePhotoAssetID: viewModel.currentProfilePhotoAssetID,
                partnerDisplayName: viewModel.currentPartnerDisplayName,
                partnerProfilePhotoAssetID: viewModel.currentPartnerProfilePhotoAssetID,
                playsIntro: viewModel.pendingPairingCelebration,
                onIntroComplete: {
                    viewModel.consumePairingCelebration()
                }
            )
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.paeoniaBackgroundPrimary)
        }
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
