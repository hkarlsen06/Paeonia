import SwiftUI
import UIKit

/// App-wide system work: post-launch warm-up, foreground passes, deep links,
/// widget sync, push registration, and banners.
extension RootView {
    /// Runs once the cold-launch intro has finished. None of this work chooses
    /// the first screen, so it waits for the entrance animation to settle.
    func runPostLaunchWork() async {
        guard !isLaunchExperienceActive else { return }

        do {
            try await Task.sleep(for: Self.postLaunchWorkDelay)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        registerForRemoteNotificationsIfSignedIn(viewModel.currentSession?.id)
        await viewModel.finishDeferredLaunchStartup()
        hasFinishedPostLaunchWork = true
        await performWidgetSyncIfPaired(viewModel.state)
    }

    /// One pass per activation. Our location refresh runs next to the
    /// foreground sync, so new content never waits on a GPS fix. Then a pending
    /// primer is offered and the partner's widget drawing is pulled. The map
    /// follows store changes itself. Quickly leaving and returning to the app
    /// while a pass runs does not start a second one.
    func runForegroundActivation() {
        // Re-arm APNs so a rotated token reaches registration; the fingerprint
        // gate drops the request when nothing changed.
        registerForRemoteNotificationsIfSignedIn(viewModel.currentSession?.id)

        guard foregroundActivationTask == nil else {
            return
        }

        foregroundActivationTask = Task {
            defer { foregroundActivationTask = nil }
            async let locationRefresh: Void = locationViewModel.refreshOwnLocationIfSharingEnabled(
                source: .foregroundOpen,
                mayPromptForAuthorization: false
            )
            async let widgetSync: Void = performWidgetSyncIfPaired(viewModel.state)
            await viewModel.refreshAfterForegroundActivation()
            if let identity = stablePairedLocationIdentity {
                presentLocationPrimerIfNeeded(for: identity)
            }
            _ = await (locationRefresh, widgetSync)
        }
    }

    @MainActor
    func handleDeepLink(_ deepLink: PaeoniaDeepLink?) async {
        guard let deepLink else {
            return
        }

        switch deepLink {
        case .widgetDrawing:
            viewModel.openWidgetDrawing()
            self.deepLink = nil
        case .dailyReveal, .dailyToday, .dailyChat:
            selectTabForDeepLink(.questions)
        case .memories:
            selectTabForDeepLink(.memories)
        case .game:
            selectTabForDeepLink(.games)
        case .streak:
            selectTabForDeepLink(.home)
        case .subscription:
            openURL(PaeoniaDeepLink.appStoreSubscriptionsURL)
            self.deepLink = nil
        }
    }

    /// Paired tab links are finished by `MainTabView`. A link that arrives
    /// before the route is known waits for it; any other route drops it.
    private func selectTabForDeepLink(_ tab: MainTab) {
        switch viewModel.state {
        case .paired, .launching:
            viewModel.selectMainTab(tab)
        default:
            deepLink = nil
        }
    }

    /// Pulls the partner's latest drawing (and our own latest) into the widget
    /// and in-app canvas whenever we're paired and the app comes forward.
    func syncWidgetIfPaired(_ state: AppState) {
        Task { await performWidgetSyncIfPaired(state) }
    }

    /// Awaitable core of the widget sync, so pull-to-refresh can keep its spinner
    /// up until the partner's drawing and avatar are staged. A privacy purge can
    /// start while the state is still `.paired`. Nothing about the partner is
    /// written while one runs, or after one started during the sync.
    func performWidgetSyncIfPaired(_ state: AppState) async {
        guard allowsSystemIntegrations, state == .paired, viewModel.inFlightAccessPrivacyPurge == nil else {
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
        await widgetCanvasSync.sync(identity: identity)
        await WidgetCenterReloader().reloadWidget()
        guard viewModel.state == .paired, viewModel.inFlightAccessPrivacyPurge == nil else {
            return
        }
        // Stage the partner's avatar so the alert can render it as a
        // communication notification while the app is in the background.
        await partnerAvatarSharing?.cachePartnerAvatar(assetID: viewModel.currentPartnerProfilePhotoAssetID)
    }

    func registerForRemoteNotificationsIfSignedIn(_ sessionID: String?) {
        guard allowsSystemIntegrations, sessionID != nil else {
            return
        }

        UIApplication.shared.registerForRemoteNotifications()
        Task {
            await widgetPushRegistration.registerCurrentWidgetPushToken()
        }
    }

    /// Pull-to-refresh on Home after the Daily Challenge refresh has run: refreshes
    /// shared local surfaces and widget sync without delaying the challenge rollover.
    func refreshHomeSurfacesFromPull() async {
        async let locationRefresh: Void = locationViewModel.refreshOwnLocationIfSharingEnabled(
            source: .manualRefresh,
            mayPromptForAuthorization: false
        )
        await performWidgetSyncIfPaired(viewModel.state)
        await locationRefresh
    }

    func showForegroundNotice(_ notice: PaeoniaForegroundNotice?) {
        guard allowsSystemIntegrations, let notice else {
            return
        }

        bannerCenter.show(
            .info(
                title: notice.title,
                message: notice.message,
                imageData: partnerAvatarData(),
                isTappable: true
            )
        )
        PaeoniaNotificationRouter.shared.consumeForegroundNotice()
    }

    /// Reads the partner avatar the app stages in the shared App Group (the same
    /// image the notification service extension uses) so the in-app notice can
    /// show the partner's face instead of a generic icon.
    private func partnerAvatarData() -> Data? {
        guard let url = PaeoniaAppGroup.containerURL?
            .appendingPathComponent(PaeoniaAppGroup.communicationPartnerAvatarPath)
        else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func showBanner(for notice: RootNotice?) {
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

    func showBanner(for notice: LocationMapViewModel.Notice?) {
        guard let notice else {
            return
        }

        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message(partnerName: partnerNameForCopy))
            )
        )
        locationViewModel.dismissNotice()
    }

    var partnerNameForCopy: String {
        viewModel.currentPartnerDisplayName?.trimmedNonEmpty
            ?? String(localized: .pairingCelebrationPartnerName)
    }

    /// What the automatic location feeds depend on. See `LocationUpdateController`.
    struct LocationUpdateInputs: Equatable {
        let identity: LocationIdentity
        /// `nil` until the sharing choice has loaded.
        let sharingEnabled: Bool?
        let isAppActive: Bool
    }

    var locationUpdateInputs: LocationUpdateInputs {
        LocationUpdateInputs(
            identity: locationIdentity,
            sharingEnabled: locationViewModel.hasResolvedSharingPreference ? locationViewModel.sharingEnabled : nil,
            isAppActive: scenePhase == .active
        )
    }

    func locationUpdateInputsChanged(to inputs: LocationUpdateInputs) {
        guard allowsSystemIntegrations else { return }
        let controller = LocationUpdateController.shared
        controller.onLocationWhileOpen = { [locationViewModel] location in
            await locationViewModel.submitObservedLocation(location)
        }
        controller.update(
            identity: inputs.identity,
            sharingEnabled: inputs.sharingEnabled,
            isAppActive: inputs.isAppActive
        )
    }
}
