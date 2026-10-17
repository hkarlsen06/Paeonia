import Foundation
import SwiftUI
import UIKit

/// The app root. It mounts the cold-launch intro and the shared top banner,
/// routes between the signed-out, setup, pairing, paywall, and paired screens,
/// and runs app-wide work such as deep links, widget sync, and permission
/// primers. Screens live in `RootView+Screens.swift`, user actions in
/// `RootView+Actions.swift`, system integration in `RootView+System.swift`,
/// the primers in `RootView+PermissionPrimers.swift`, and the usage question
/// in `RootView+UsageSharing.swift`.
struct RootView: View {
    @State var viewModel: RootViewModel
    @State var locationViewModel: LocationMapViewModel
    @State var bannerCenter = PaeoniaBannerCenter()
    @State var isLaunchExperienceActive = true
    @State var launchContentRevealed = false
    @State var launchSidesUncovered = false
    @State var permissionPrimerCoordinator: RootPairingPermissionPrimerCoordinator
    /// Checks and joins a partner's code. One instance serves the paywall, the
    /// invite screen and the join screen, so a code typed on either of the first
    /// two is checked once.
    @State var pairingJoinViewModel: PairingJoinViewModel
    /// The first day sequence after the pairing celebration. It starts loading
    /// while the celebration plays.
    @State var postPairingFlow: PostPairingFlowModel
    @State var hasFinishedPostLaunchWork = false
    /// The running foreground pass. A second activation while it runs is
    /// skipped instead of starting an overlapping pass.
    @State var foregroundActivationTask: Task<Void, Never>?
    /// An invite link opened the app before the route was known. If the route
    /// turns out to be paired, the root explains why the link did nothing.
    @State var joinLinkOpenedDuringLaunch = false
    /// A permission primer appeared since the app last came to the front. Only
    /// one is offered per visit; the flag resets when the app goes to the background.
    @State var primerShownThisVisit = false
    /// One of the invite screen's first day tasks is open. A partner who joins
    /// meanwhile waits on the invite screen until it closes, then the celebration plays.
    @State var inviterTaskIsOpen = false
    /// The paired person's answer to "Help us improve Paeonia?".
    @State var usageSharing = UsageSharingModel()
    /// The usage statistics question is showing. It takes a primer's turn.
    @State var isUsageQuestionPresented = false
    @Binding var deepLink: PaeoniaDeepLink?
    @Binding var pendingJoinInviteCode: String?
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) var scenePhase
    let appleSignInProvider: any AppleSignInProviding
    let widgetCanvasService: any WidgetCanvasManaging
    let widgetCanvasSync: any WidgetCanvasSyncing
    let pushAuthorization: any PushAuthorizationProviding
    let widgetPushRegistration: any WidgetPushRegistering
    let partnerAvatarSharing: (any PartnerAvatarSharing)?
    let featureDependencies: RootFeatureDependencies
    let allowsSystemIntegrations: Bool
    /// Lets the first screen's entrance animation settle before sync, widget, avatar,
    /// and APNs warm-up begin. None of this work is required to choose the route.
    static let postLaunchWorkDelay: Duration = .milliseconds(700)

    /// `viewModel` and `locationViewModel` should be created once by the owner
    /// (see `PaeoniaApp`). The defaults build new ones, and this initializer runs
    /// on every parent update, so only previews and tests should rely on them.
    @MainActor
    init(
        deepLink: Binding<PaeoniaDeepLink?> = .constant(nil),
        pendingJoinInviteCode: Binding<String?> = .constant(nil),
        viewModel: RootViewModel? = nil,
        locationViewModel: LocationMapViewModel? = nil,
        appleSignInProvider: (any AppleSignInProviding)? = nil,
        widgetCanvasService: (any WidgetCanvasManaging)? = nil,
        widgetCanvasSync: (any WidgetCanvasSyncing)? = nil,
        pushAuthorization: (any PushAuthorizationProviding)? = nil,
        pushPermissionPrimerStore: (any PushPermissionPrimerPersisting)? = nil,
        locationSharingPrimerStore: (any LocationSharingPrimerPersisting)? = nil,
        widgetPushRegistration: (any WidgetPushRegistering)? = nil,
        partnerAvatarSharing: (any PartnerAvatarSharing)? = nil,
        featureDependencies: RootFeatureDependencies? = nil,
        allowsSystemIntegrations: Bool = true
    ) {
        let resolvedViewModel = viewModel ?? RootViewModel()
        _viewModel = State(initialValue: resolvedViewModel)
        _locationViewModel = State(initialValue: locationViewModel ?? LocationMapViewModel())
        _permissionPrimerCoordinator = State(
            initialValue: RootPairingPermissionPrimerCoordinator(
                pushPrimerStore: pushPermissionPrimerStore
                    ?? UserDefaultsPushPermissionPrimerStore(),
                locationPrimerStore: locationSharingPrimerStore
                    ?? UserDefaultsLocationSharingPrimerStore()
            )
        )
        _pairingJoinViewModel = State(
            initialValue: featureDependencies?.pairingJoinViewModel ?? PairingJoinViewModel()
        )
        _postPairingFlow = State(
            initialValue: PostPairingFlowModel(
                store: resolvedViewModel.pairingCelebrationStore,
                milestoneViewModel: featureDependencies?.milestoneViewModel,
                drawingViewModel: featureDependencies?.widgetDrawingViewModel
            )
        )
        _deepLink = deepLink
        _pendingJoinInviteCode = pendingJoinInviteCode
        self.appleSignInProvider = appleSignInProvider ?? AppleSignInService()
        self.widgetCanvasService = widgetCanvasService ?? WidgetCanvasService.shared
        self.widgetCanvasSync = widgetCanvasSync ?? WidgetCanvasSyncServiceFactory.makeDefault()
        self.pushAuthorization = pushAuthorization ?? PushAuthorizationService()
        self.widgetPushRegistration = widgetPushRegistration ?? WidgetPushRegistrationServiceFactory.makeDefault()
        self.partnerAvatarSharing = partnerAvatarSharing ?? PartnerAvatarSharingServiceFactory.makeDefault()
        self.featureDependencies = featureDependencies ?? RootFeatureDependencies()
        self.allowsSystemIntegrations = allowsSystemIntegrations
    }

    var body: some View {
        rootContent
            .environment(bannerCenter)
            // Developer flows skip the usage question and switch.
            .environment(allowsSystemIntegrations ? usageSharing : nil)
            .task {
                locationViewModel.setLocalChangeSyncHandler {
                    await viewModel.syncAfterLocalLocationChange()
                }
                await viewModel.start(deferringSyncUntilLaunchCompletes: true)
            }
            .task(id: isLaunchExperienceActive) {
                await runPostLaunchWork()
            }
            .preferredColorScheme(.dark)
            // Handle deep links from an async task (fires on appear and whenever
            // the link changes) so navigation state is never mutated
            // synchronously during a view update.
            .task(id: deepLink) {
                handleDeepLink(deepLink)
            }
            .task(id: locationIdentity) {
                await locationViewModel.configure(identity: locationIdentity)
            }
            // A local snapshot paints immediately. Once the paired surface is
            // stable, wait for the server-backed read model, then republish it
            // into the view model so location consent survives privacy purges,
            // sign-out/sign-in, reinstall, and ordinary app restarts.
            .task(id: stablePairedLocationIdentity) {
                guard let stableIdentity = stablePairedLocationIdentity else {
                    return
                }
                await restorePairedLocationPresentation(for: stableIdentity)
            }
            .onChange(of: viewModel.notice) { _, notice in
                showBanner(for: notice)
            }
            .onChange(of: locationViewModel.notice) { _, notice in
                showBanner(for: notice)
            }
            .onChange(of: viewModel.currentSession?.id, initial: true) { previousUserID, userID in
                sessionChanged(from: previousUserID, to: userID)
            }
            .task(id: usageSharingUserID) {
                guard allowsSystemIntegrations else {
                    return
                }
                await usageSharing.follow(usageSharingUserID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .paeoniaSubscriptionDidUpdate)) { _ in
                guard allowsSystemIntegrations else {
                    return
                }
                subscriptionChanged()
            }
            // A partner's widget update arrived while the app is open: the delegate
            // suppressed the system banner and relayed it here for the in-app one.
            .onChange(of: PaeoniaNotificationRouter.shared.pendingForegroundNotice) { _, notice in
                showForegroundNotice(notice)
            }
            .onChange(of: viewModel.state) { _, state in
                stateChanged(to: state)
            }
            .onChange(of: locationUpdateInputs, initial: true) { _, inputs in
                locationUpdateInputsChanged(to: inputs)
            }
            .onChange(of: pendingJoinInviteCode) { _, code in
                pendingJoinInviteCodeChanged(to: code)
            }
            .onChange(of: scenePhase) { oldPhase, phase in
                if phase == .background {
                    primerShownThisVisit = false
                }
                // The Lock Screen widgets come into view as the app leaves, so
                // one reload here picks up everything that changed while it was open.
                if oldPhase == .active, phase == .inactive, allowsSystemIntegrations {
                    LockScreenWidgetReloader.reload()
                }
                // A no given on another phone stops counting here too.
                if phase == .active, allowsSystemIntegrations {
                    Task {
                        await usageSharing.refresh()
                    }
                }
                guard phase == .active, !isLaunchExperienceActive else {
                    return
                }
                runForegroundActivation()
            }
            .paeoniaTopBanner(bannerCenter) {
                // Tapping a partner-update notice opens the drawing screen, the
                // same destination the notification tap routes to.
                viewModel.openWidgetDrawing()
            }
            .alert(
                Text(.authDeleteAccountAppleManualTitle),
                isPresented: manualAppleRevocationBinding
            ) {
                manualAppleRevocationActions
            } message: {
                Text(.authDeleteAccountAppleManualMessage)
            }
            .sheet(item: pairingPermissionPrimerBinding) { primer in
                permissionPrimerSheet(primer)
            }
    }

    @ViewBuilder
    private var manualAppleRevocationActions: some View {
        Button {
            viewModel.dismissManualAppleRevocation()
            if let url = URL(string: "https://account.apple.com/") {
                openURL(url)
            }
        } label: {
            Text(.authDeleteAccountAppleManualOpenButton)
        }

        Button(role: .cancel) {
            viewModel.dismissManualAppleRevocation()
        } label: {
            Text(.authDeleteAccountAppleManualDoneButton)
        }
    }

    private var manualAppleRevocationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.requiresManualAppleRevocation },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissManualAppleRevocation()
                }
            }
        )
    }

    var widgetDrawingPresented: Binding<Bool> {
        Binding(
            get: {
                viewModel.presentedDestination == .widgetDrawing
            },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissPresentedDestination()
                }
            }
        )
    }

    var mainTabSelection: Binding<MainTab> {
        Binding(
            get: { viewModel.selectedMainTab },
            set: { viewModel.selectMainTab($0) }
        )
    }

    private var rootContent: some View {
        ZStack {
            routedRootContent
                // The intro cues the surface to cascade its content in as it exits, and
                // the Home map's flame sweep waits until the opening hole reaches the
                // screen's sides so it doesn't play hidden behind the overlay.
                .environment(\.launchContentRevealed, launchContentRevealed)
                .environment(\.launchSidesUncovered, launchSidesUncovered)
                .environment(\.launchIntroComplete, !isLaunchExperienceActive)
                .zIndex(0)

            if isLaunchExperienceActive {
                // The intro drives its own timeline and tells us when to cue the content
                // (`onRevealContent`) and when it has fully exited (`onFinished`), so the
                // overlay stays mounted past the moment `state` leaves `.launching`.
                LaunchExperienceView(
                    contentReady: viewModel.state != .launching,
                    onRevealContent: { launchContentRevealed = true },
                    onSidesUncovered: { launchSidesUncovered = true },
                    onFinished: {
                        isLaunchExperienceActive = false
                    }
                )
                .transition(.identity)
                .zIndex(1)
            }
        }
        .sheet(isPresented: usageSharingQuestionBinding) {
            UsageSharingQuestionView { shares in
                Task {
                    await usageSharing.answer(shares)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .background(.paeoniaBackgroundPrimary)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
    }
}

#Preview {
    RootView()
}
