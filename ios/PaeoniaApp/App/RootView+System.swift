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
    /// foreground sync, so new content never waits on a GPS fix. The map
    /// follows store changes itself, and `WidgetCanvasLiveFeed` pulls the
    /// partner's widget drawing, so the widget pass only sends a drawing that
    /// is still waiting. Quickly leaving and returning to the app while a pass
    /// runs does not start a second one.
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
            async let widgetSync: Void = performWidgetSyncIfPaired(
                viewModel.state,
                syncsCanvas: WidgetPendingUploadStore.shared.hasPending
            )
            await viewModel.refreshAfterForegroundActivation()
            await SignInMethodsServerSync.retryIfPending()
            _ = await (locationRefresh, widgetSync)
        }
    }

    /// A notification tap or link that arrives while the app is locked waits for
    /// the unlock. Handling it again when the lock opens routes it then.
    var isHeldByAppLock: Bool {
        allowsSystemIntegrations && AppLockModel.shared.isLocked
    }

    /// The link the tabs see. Nothing while the lock is closed, so the tabs open
    /// it only after the unlock.
    var deepLinkForTabs: Binding<PaeoniaDeepLink?> {
        Binding(
            get: { isHeldByAppLock ? nil : deepLink },
            set: { deepLink = $0 }
        )
    }

    var deepLinkDelivery: DeepLinkDelivery {
        DeepLinkDelivery(link: deepLink, isHeldByAppLock: isHeldByAppLock, isRouteKnown: viewModel.state != .launching)
    }

    /// Changes when a link arrives or the lock opens, which restarts the handling task.
    struct DeepLinkDelivery: Equatable {
        let link: PaeoniaDeepLink?
        let isHeldByAppLock: Bool
        /// The launch has finished, so links that need to know the sign-in state can be handled.
        let isRouteKnown: Bool
    }

    @MainActor
    func handleDeepLink(_ deepLink: PaeoniaDeepLink?) {
        guard let deepLink, !isHeldByAppLock else {
            return
        }

        switch deepLink {
        case .widgetDrawing:
            viewModel.openWidgetDrawing()
            self.deepLink = nil
        case .dailyReveal, .dailyToday, .dailyChat, .gameChat, .topics:
            selectTabForDeepLink(.questions)
        case .memories, .memory:
            selectTabForDeepLink(.memories)
        case .game:
            selectTabForDeepLink(.games)
        case .streak, .stories, .story, .home, .dates, .firstDayAnswer:
            selectTabForDeepLink(.home)
        case .subscription:
            openURL(PaeoniaDeepLink.appStoreSubscriptionsURL)
            self.deepLink = nil
        case .dataExport:
            openDataExport()
        }
    }

    /// Opens the data download screen over whatever is showing, since it works with or without a
    /// subscription. A link that arrives during launch waits until the sign-in state is known.
    @MainActor
    private func openDataExport() {
        switch viewModel.state {
        case .launching:
            return
        case .unauthenticated, .accountClosed, .deletingAccount:
            break
        default:
            viewModel.isShowingDataExport = true
        }
        deepLink = nil
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

    /// The name this person sees for their partner changed, either because they set or cleared a
    /// nickname or because the partner renamed themselves. Saves the new name for the widgets,
    /// relabels the drawing the Home Screen widget shows, and rebuilds the Lock Screen widgets.
    func partnerNameChanged() {
        guard allowsSystemIntegrations, viewModel.state == .paired else {
            return
        }
        syncWidgetIfPaired(viewModel.state)
        LockScreenWidgetReloader.reload()
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
    /// `syncsCanvas` false only saves the names and stages the avatar. The canvas
    /// service reloads the widget itself when it saves a new drawing.
    func performWidgetSyncIfPaired(_ state: AppState, syncsCanvas: Bool = true) async {
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
        if syncsCanvas {
            await widgetCanvasSync.sync(identity: identity)
        }
        guard viewModel.state == .paired, viewModel.inFlightAccessPrivacyPurge == nil else {
            return
        }
        // Stage the partner's avatar so the alert can render it as a
        // communication notification while the app is in the background.
        await partnerAvatarSharing?.cachePartnerAvatar(assetID: viewModel.currentPartnerProfilePhotoAssetID)
    }

    /// The partner photo that alerts and in-app banners show. A new photo, or the
    /// partner removing theirs, changes it while the app is open.
    var partnerAvatarIdentity: PartnerAvatarIdentity? {
        guard allowsSystemIntegrations, viewModel.state == .paired,
              let coupleID = viewModel.currentActiveCoupleID
        else {
            return nil
        }

        return PartnerAvatarIdentity(coupleID: coupleID, assetID: viewModel.currentPartnerProfilePhotoAssetID)
    }

    /// Stages the partner's photo for alerts and banners, and tries again after a
    /// failed download until it is staged or the photo changes.
    func stagePartnerAvatar(_ identity: PartnerAvatarIdentity?) async {
        guard let identity, let partnerAvatarSharing else {
            return
        }

        _ = await ProfilePhotoRetry.load { () async -> Bool? in
            // Nothing about the partner is written while a privacy purge runs.
            guard viewModel.inFlightAccessPrivacyPurge == nil else {
                return true
            }
            return await partnerAvatarSharing.cachePartnerAvatar(assetID: identity.assetID) ? true : nil
        }
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
                imageData: notice.showsPartnerAvatar ? PaeoniaAppGroup.partnerAvatarData() : nil,
                action: notice.deepLink.map { deepLink in
                    { PaeoniaNotificationRouter.shared.route(deepLink) }
                }
            )
        )
        PaeoniaNotificationRouter.shared.consumeForegroundNotice()
    }

    func showBanner(for notice: RootNotice?) {
        guard let notice else {
            return
        }

        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message),
                timing: notice.bannerTiming
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
                message: String(localized: notice.message(partnerName: partnerNameForCopy)),
                // Location permission is fixed in Settings, after the banner would have gone.
                timing: notice == .permissionDenied ? .untilDismissed : .standard
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
        /// Sharing is on but paused. The live feed stops until the pause ends.
        let isSharingPaused: Bool
        let isAppActive: Bool
    }

    var locationUpdateInputs: LocationUpdateInputs {
        LocationUpdateInputs(
            identity: locationIdentity,
            sharingEnabled: locationViewModel.hasResolvedSharingPreference ? locationViewModel.sharingEnabled : nil,
            isSharingPaused: locationViewModel.isSharingPaused,
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
            isSharingPaused: inputs.isSharingPaused,
            isAppActive: inputs.isAppActive
        )
    }
}

struct PartnerAvatarIdentity: Equatable {
    let coupleID: UUID
    let assetID: UUID?
}
