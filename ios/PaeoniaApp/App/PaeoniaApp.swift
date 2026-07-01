import GoogleSignIn
import SwiftUI

@main
struct PaeoniaApp: App {
    @UIApplicationDelegateAdaptor(PaeoniaAppDelegate.self) private var appDelegate
    @State private var deepLink: PaeoniaDeepLink?
    @State private var pendingJoinInviteCode = UserDefaultsPairingJoinInviteStore.shared.loadInviteCode()
    @State private var notificationRouter = PaeoniaNotificationRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView(
                deepLink: $deepLink,
                pendingJoinInviteCode: $pendingJoinInviteCode
            )
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) {
                    return
                }

                if let deepLink = PaeoniaDeepLink(url) {
                    self.deepLink = deepLink
                    return
                }

                if let inviteCode = PairingJoinURL.inviteCode(from: url) {
                    pendingJoinInviteCode = inviteCode
                    return
                }

                PaeoniaSupabaseClientProvider.shared.handle(url)
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
}
