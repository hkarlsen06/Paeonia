import ClerkKit
import SwiftUI

@main
struct PaeoniaApp: App {
    @UIApplicationDelegateAdaptor(PaeoniaAppDelegate.self) private var appDelegate
    @State private var deepLink: PaeoniaDeepLink?
    @State private var pendingJoinInviteCode = UserDefaultsPairingJoinInviteStore.shared.loadInviteCode()
    @State private var notificationRouter = PaeoniaNotificationRouter.shared
    /// Built once here. `RootView`'s initializer runs on every update of this
    /// body, so defaults built there would be made and thrown away each time.
    @State private var rootViewModel: RootViewModel
    @State private var locationViewModel: LocationMapViewModel
    #if DEBUG
    @State private var developerDestination = DeveloperScenarioLaunch.destination()
    #endif

    init() {
        // Clerk must be configured before anything reads `Clerk.shared`. An empty
        // publishable key leaves it unconfigured and auth reports itself unavailable.
        // The view models below read it, so they are created after this call.
        let usesClerk = !Self.isHostingUnitTests && PaeoniaClerk.configureIfPossible()
        if !Self.isHostingUnitTests {
            PaeoniaAnalytics.configure()
        }
        let sessionIsActive: (@MainActor () -> Bool?)? = usesClerk ? Self.clerkSessionIsActive : nil
        let appleIsLinked: (@MainActor () async -> Bool)? = usesClerk ? ClerkSignInMethodLinker.appleIsLinked : nil
        _rootViewModel = State(
            initialValue: RootViewModel(
                authProviderSessionIsActive: sessionIsActive,
                appleIsLinked: appleIsLinked
            )
        )
        _locationViewModel = State(initialValue: LocationMapViewModel())
    }

    var body: some Scene {
        WindowGroup {
            appContent
            .onOpenURL { url in
                if let deepLink = PaeoniaDeepLink(url) {
                    self.deepLink = deepLink
                    return
                }

                if let inviteCode = PairingJoinURL.inviteCode(from: url) {
                    pendingJoinInviteCode = inviteCode
                }
            }
            .onChange(of: pendingJoinInviteCode) { _, inviteCode in
                if let inviteCode {
                    UserDefaultsPairingJoinInviteStore.shared.saveInviteCode(inviteCode)
                } else {
                    UserDefaultsPairingJoinInviteStore.shared.clearInviteCode()
                }
            }
            // Tapped notifications route through the same typed deep-link path
            // as app URLs, so launches, widgets, and pushes share navigation.
            .onChange(of: notificationRouter.pendingDeepLink, initial: true) { _, deepLink in
                guard let deepLink else {
                    return
                }

                self.deepLink = deepLink
                notificationRouter.consumePendingDeepLink()
            }
        }
    }

    /// Unit tests run inside this app. The real app would sign in, sync and write
    /// the same local stores the tests use, and slow every test run down.
    private static let isHostingUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    @ViewBuilder
    private var appContent: some View {
        if Self.isHostingUnitTests {
            Color.clear
        } else {
            launchedContent
        }
    }

    @ViewBuilder
    private var launchedContent: some View {
        #if DEBUG
        switch developerDestination {
        case .production:
            productionRoot
        case .menu:
            DeveloperScenarioMenu {
                developerDestination = .production
            }
        case .scenario(let scenario):
            DeveloperScenarioHost(scenario: scenario) {
                developerDestination = .menu
            }
        case .tour:
            DeveloperScenarioTour()
        }
        #else
        productionRoot
        #endif
    }

    /// Whether Clerk still holds an active session, read from its observable
    /// state without a network call. `nil` until Clerk has loaded, so a cold
    /// launch is never mistaken for a sign-out.
    @MainActor
    private static func clerkSessionIsActive() -> Bool? {
        guard Clerk.shared.isLoaded else {
            return nil
        }
        return PaeoniaClerk.currentAccountID() != nil
    }

    private var productionRoot: some View {
        RootView(
            deepLink: $deepLink,
            pendingJoinInviteCode: $pendingJoinInviteCode,
            viewModel: rootViewModel,
            locationViewModel: locationViewModel
        )
    }
}
