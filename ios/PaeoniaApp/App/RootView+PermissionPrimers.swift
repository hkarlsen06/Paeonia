import SwiftUI

/// The one-time notification and location primers.
/// `RootPairingPermissionPrimerCoordinator` decides which primer is due; this
/// extension supplies the paired identity, the sheets, and their actions.
extension RootView {
    var locationIdentity: LocationIdentity {
        LocationIdentity(
            currentUserID: viewModel.currentSession.flatMap { UUID(uuidString: $0.id) },
            coupleID: viewModel.currentActiveCoupleID
        )
    }

    /// The paired identity once Home is actually on screen: after launch work,
    /// and never under the pairing celebration or the first day sequence.
    var stablePairedLocationIdentity: LocationIdentity? {
        guard hasFinishedPostLaunchWork,
              viewModel.state == .paired,
              !viewModel.isPairingCelebrationPresented,
              !viewModel.isFirstDayPresented,
              locationIdentity.currentUserID != nil,
              locationIdentity.coupleID != nil
        else {
            return nil
        }

        return locationIdentity
    }

    func isCurrentStableIdentity(_ identity: LocationIdentity) -> Bool {
        !Task.isCancelled && stablePairedLocationIdentity == identity
    }

    /// Runs when Home becomes the stable paired surface. Restores the
    /// server-backed sharing preference that the location primer needs.
    func restorePairedLocationPresentation(for identity: LocationIdentity) async {
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            return
        }

        await viewModel.synchronizePairedPresentationData()
        guard isCurrentStableIdentity(identity) else { return }

        // Configure again rather than assuming the cache-first task has already
        // settled; both tasks can become eligible after a fast sign-in transition.
        await locationViewModel.configure(identity: identity)
        guard isCurrentStableIdentity(identity) else { return }

        // A fresh install may restore an enabled server preference while iOS
        // permission is undecided. The primer remains the only prompting path.
        await locationViewModel.refreshOwnLocationIfSharingEnabled(
            source: .foregroundOpen,
            mayPromptForAuthorization: false
        )
    }

    /// Nothing asks for permission when the app opens. The primers wait until
    /// the person has answered a question or sent a drawing, and show once the
    /// answer cover or the drawing screen has gone away. Notifications come
    /// first, then location, then the usage statistics question. At most one
    /// shows per visit, so each later one waits for a later visit.
    func offerPrimersAfterSharing() {
        guard allowsSystemIntegrations,
              !primerShownThisVisit,
              let identity = stablePairedLocationIdentity
        else {
            return
        }

        Task { @MainActor in
            await permissionPrimerCoordinator.presentNotificationPrimerIfNeeded(
                identity: identity,
                pushAuthorization: pushAuthorization
            )
            if permissionPrimerCoordinator.presentedPrimer == nil, isCurrentStableIdentity(identity) {
                permissionPrimerCoordinator.presentLocationPrimerIfNeeded(
                    identity: identity,
                    sharingStateIsKnown: locationViewModel.hasResolvedSharingPreference,
                    sharingEnabled: locationViewModel.sharingEnabled,
                    locationAuthorizationState: locationViewModel.authorizationState
                )
            }

            // The authorization status read can outlive the paired identity.
            // Never let that stale result resurrect a primer after unpair/sign-out.
            if !isCurrentStableIdentity(identity),
               permissionPrimerCoordinator.presentedIdentity == identity {
                permissionPrimerCoordinator.dismiss()
            }

            if permissionPrimerCoordinator.presentedPrimer != nil {
                primerShownThisVisit = true
            } else if usageSharing.needsAnswer, isCurrentStableIdentity(identity) {
                isUsageQuestionPresented = true
                primerShownThisVisit = true
            }
        }
    }

    var pairingPermissionPrimerBinding: Binding<RootPairingPermissionPrimerCoordinator.Primer?> {
        Binding(
            get: { permissionPrimerCoordinator.presentedPrimer },
            set: { primer in
                // Both sheets disable swipe-to-dismiss, so this only runs when the
                // system closes one. Nothing is recorded; the primer stays eligible.
                if primer == nil {
                    permissionPrimerCoordinator.dismiss()
                }
            }
        )
    }

    @ViewBuilder
    func permissionPrimerSheet(_ primer: RootPairingPermissionPrimerCoordinator.Primer) -> some View {
        switch primer {
        case .location:
            LocationSharingPrimerView(
                partnerName: partnerNameForCopy,
                onShare: enableLocationSharing,
                onNotNow: dismissLocationSharingPrimer
            )
            .analyticsScreen("location_primer")
        case .notifications:
            PushPermissionPrimerView(
                partnerName: partnerNameForCopy,
                onEnable: enablePushNotifications,
                onNotNow: dismissPushPermissionPrimer
            )
            .analyticsScreen("push_primer")
        }
    }

    private func enableLocationSharing() {
        permissionPrimerCoordinator.markLocationResponded(identity: locationIdentity)
        permissionPrimerCoordinator.dismiss()
        Task { @MainActor in
            await shareLocation()
        }
    }

    /// Turns sharing on, asking iOS for While Using first. Once that is
    /// allowed, iOS asks right away whether Paeonia may also share while closed.
    /// A plain retry, with sharing and access already on, asks nothing.
    func shareLocation() async {
        let wasAlreadyAllowed = locationViewModel.sharingEnabled
            && locationViewModel.authorizationState == .authorized
        await locationViewModel.promptForCurrentLocation()
        guard !wasAlreadyAllowed,
              locationViewModel.sharingEnabled,
              locationViewModel.authorizationState == .authorized
        else {
            return
        }
        LocationUpdateController.shared.offerUpdatesWhileClosed()
    }

    private func dismissLocationSharingPrimer() {
        permissionPrimerCoordinator.markLocationResponded(identity: locationIdentity)
        permissionPrimerCoordinator.dismiss()
    }

    private func enablePushNotifications() {
        permissionPrimerCoordinator.dismiss()
        Task { @MainActor in
            let didSettleAuthorization = await pushAuthorization.requestAuthorizationIfNeeded()
            // Persist only after the call has reached and settled the system
            // authorization flow. If the app is terminated before then, the
            // primer remains eligible on the next launch instead of disappearing
            // forever while iOS is still `.notDetermined`.
            if didSettleAuthorization {
                permissionPrimerCoordinator.markPushResponded()
            }
        }
    }

    private func dismissPushPermissionPrimer() {
        permissionPrimerCoordinator.markPushResponded()
        permissionPrimerCoordinator.dismiss()
    }
}
