import SwiftUI

/// The one-time notification and location primers shown after pairing.
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
    /// and never under the pairing celebration.
    var stablePairedLocationIdentity: LocationIdentity? {
        guard hasFinishedPostLaunchWork,
              viewModel.state == .paired,
              !viewModel.isPairingCelebrationPresented,
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

    /// Runs when Home becomes the stable paired surface. The notification primer
    /// is offered first, once Home has finished sliding in, because it needs no
    /// server data. The location primer needs the server-backed sharing
    /// preference, which the sync pass below restores, and is only offered when
    /// no other primer was shown during this visit.
    func restorePairedLocationPresentation(for identity: LocationIdentity) async {
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            return
        }
        await presentPermissionPrimerIfNeeded(for: identity)
        guard isCurrentStableIdentity(identity) else { return }

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
        guard isCurrentStableIdentity(identity) else { return }

        await presentPermissionPrimerIfNeeded(for: identity)
    }

    /// Offers at most one primer per visit. Two permission asks back to back
    /// feel pushy, so after the notification primer the location primer waits
    /// until the person next comes back to the app.
    func presentPermissionPrimerIfNeeded(for identity: LocationIdentity) async {
        guard allowsSystemIntegrations,
              !primerShownThisVisit,
              isCurrentStableIdentity(identity)
        else {
            return
        }

        await permissionPrimerCoordinator.presentIfNeeded(
            identity: identity,
            sharingStateIsKnown: locationViewModel.hasResolvedSharingPreference,
            sharingEnabled: locationViewModel.sharingEnabled,
            locationAuthorizationState: locationViewModel.authorizationState,
            pushAuthorization: pushAuthorization
        )

        // Scene-activation work is intentionally unstructured and can outlive
        // the paired identity while the authorization status read is suspended.
        // Never let that stale result resurrect a primer after unpair/sign-out.
        if !isCurrentStableIdentity(identity),
           permissionPrimerCoordinator.presentedIdentity == identity {
            permissionPrimerCoordinator.dismiss()
        }

        if permissionPrimerCoordinator.presentedPrimer != nil {
            primerShownThisVisit = true
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
        case .notifications:
            PushPermissionPrimerView(
                partnerName: partnerNameForCopy,
                onEnable: enablePushNotifications,
                onNotNow: dismissPushPermissionPrimer
            )
        }
    }

    private func enableLocationSharing() {
        permissionPrimerCoordinator.markLocationResponded(identity: locationIdentity)
        permissionPrimerCoordinator.dismiss()
        Task { @MainActor in
            await locationViewModel.promptForCurrentLocation()
        }
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
