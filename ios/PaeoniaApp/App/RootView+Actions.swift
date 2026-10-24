import SwiftUI

/// User actions the routed screens forward to the root, and the root's
/// reactions to session, state, and invite-code changes.
extension RootView {
    func signInWithApple() {
        Task {
            await viewModel.signInWithApple(using: appleSignInProvider)
        }
    }

    func signInWithGoogle() {
        Task {
            await viewModel.signInWithGoogle()
        }
    }

    /// Stashes an invite code a joining partner entered before signing in. After
    /// sign-in the root shows the join screen for it. The binding owner persists
    /// production changes, so this view stays safe to host with an in-memory
    /// binding in local flows and previews.
    func captureInviteCode(_ code: String) {
        pendingJoinInviteCode = code
    }

    /// A code typed on the paywall, the invite screen or the join screen. Once it
    /// checks out it becomes the pending code, which shows the join screen for it.
    /// Otherwise the banner says why, and the code sheet stays open.
    func submitJoinCode(_ code: String) async -> Bool {
        guard await pairingJoinViewModel.checkCode(code, currentUserID: viewModel.currentSession?.id),
              let checkedCode = pairingJoinViewModel.checkedCode
        else {
            if let error = pairingJoinViewModel.lastError {
                bannerCenter.show(.error(message: String(localized: error.message)))
            }
            return false
        }

        pendingJoinInviteCode = checkedCode
        return true
    }

    func completeOnboarding(displayName: String, profilePhotoData: Data?) {
        Task {
            await viewModel.completeOnboarding(
                displayName: displayName,
                timeZoneID: TimeZone.current.identifier,
                profilePhotoData: profilePhotoData
            )
        }
    }

    func signOut() {
        Task {
            await viewModel.signOut()
        }
    }

    func deleteAccount() {
        Task {
            await viewModel.deleteAccount(reauthenticatingWith: appleSignInProvider)
        }
    }

    func subscriptionChanged() {
        Task {
            await viewModel.refreshAfterSubscriptionChange()
        }
    }

    func inviteAccepted() {
        Task {
            await viewModel.refreshAfterInviteAccepted()
            pendingJoinInviteCode = nil
        }
    }

    func refreshPairing() {
        Task {
            await viewModel.refreshAfterPairingChange()
        }
    }

    func acknowledgeRelationshipEnded() {
        Task {
            await viewModel.acknowledgeRelationshipEnded()
        }
    }

    func dismissPairingCelebration() {
        withAnimation(pairedScreenAnimation) {
            viewModel.dismissPairingCelebration()
        }
    }

    /// The first day sequence ended. "Answer now" goes on to the answer flow,
    /// which `MainTabView` opens for the deep link.
    func finishFirstDay(_ outcome: PostPairingOutcome) {
        if outcome == .answerQuestions {
            deepLink = .dailyToday(coupleDayID: nil)
        }
        withAnimation(pairedScreenAnimation) {
            viewModel.finishFirstDay()
        }
    }

    func sessionChanged(from previousUserID: String?, to userID: String?) {
        // An invite code belongs to the person who was signed in. Clear it once
        // their session goes away or someone else's starts, whether they signed
        // out, deleted the account, or the session ended on its own. A code saved
        // while signed out stays for whoever signs in next.
        if !Self.keepsJoinInviteCode(from: previousUserID, to: userID) {
            pendingJoinInviteCode = nil
        }

        guard allowsSystemIntegrations else {
            return
        }

        if let userID {
            PaeoniaStoreKitService.shared.configure(userID: userID)
        } else {
            PaeoniaStoreKitService.shared.stopTransactionListener()
        }

        // Once signed in, get an APNs token so the backend can send the silent
        // push that wakes us to sync a partner's drawing. The cold launch does
        // this after the intro instead.
        if !isLaunchExperienceActive {
            registerForRemoteNotificationsIfSignedIn(userID)
        }
    }

    func stateChanged(to state: AppState) {
        if state != .paired {
            permissionPrimerCoordinator.dismiss()
        }
        switch state {
        case .paired where inviterTaskIsOpen:
            showPartnerJoinedDuringTask()
        case .paired, .unpaired, .invitePending:
            break
        default:
            // The invite screen is gone, so no task of its own is open any more.
            inviterTaskIsOpen = false
        }
        // A paired couple cannot join anyone. Drop a code left over from an
        // invite accepted just before the app closed, or saved on an old link.
        // A link that opened the app is still explained.
        if Self.blocksJoining(state) {
            let explains = joinLinkOpenedDuringLaunch && pendingJoinInviteCode != nil
            joinLinkOpenedDuringLaunch = false
            pendingJoinInviteCode = nil
            if explains {
                showAlreadyPairedNotice()
            }
        } else if state != .launching {
            joinLinkOpenedDuringLaunch = false
        }
        if !isLaunchExperienceActive {
            syncWidgetIfPaired(state)
        }
    }

    /// The partner joined while the inviter is answering. The celebration
    /// waits for the task to close, and this says why nothing else happened yet.
    private func showPartnerJoinedDuringTask() {
        bannerCenter.show(
            .info(
                title: String(localized: .pairingJoinedDuringTaskTitle(partnerNameForCopy)),
                message: String(localized: .pairingJoinedDuringTaskMessage),
                timing: .fixed(.seconds(6))
            )
        )
    }

    /// A partner's invite link opened while this person is already paired would
    /// otherwise do nothing visible, then resurface much later after an unpair.
    func pendingJoinInviteCodeChanged(to code: String?) {
        guard code != nil else {
            pairingJoinViewModel.clearCheckedCode()
            return
        }

        if viewModel.state == .launching {
            joinLinkOpenedDuringLaunch = true
            return
        }

        guard Self.blocksJoining(viewModel.state) else {
            return
        }

        pendingJoinInviteCode = nil
        showAlreadyPairedNotice()
    }

    private func showAlreadyPairedNotice() {
        bannerCenter.show(
            .info(
                title: String(localized: .rootJoinLinkAlreadyPairedTitle),
                message: String(localized: .rootJoinLinkAlreadyPairedMessage),
                systemImage: "heart.fill"
            )
        )
    }

    static func keepsJoinInviteCode(from previousUserID: String?, to userID: String?) -> Bool {
        guard let previousUserID else { return true }
        return userID.map { AuthUserIdentity.matches(previousUserID, $0) } ?? false
    }

    private static func blocksJoining(_ state: AppState) -> Bool {
        state == .paired || state == .pairedPaywalled
    }
}
