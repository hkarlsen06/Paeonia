import GoogleSignIn
import SwiftUI

@main
struct PaeoniaApp: App {
    @UIApplicationDelegateAdaptor(PaeoniaAppDelegate.self) private var appDelegate
    @State private var widgetDeepLink: PaeoniaWidgetDeepLink?
    @State private var pendingJoinInviteCode = UserDefaultsPairingJoinInviteStore.shared.loadInviteCode()
    @State private var notificationRouter = PaeoniaNotificationRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView(
                widgetDeepLink: $widgetDeepLink,
                pendingJoinInviteCode: $pendingJoinInviteCode
            )
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) {
                    return
                }

                if let widgetDeepLink = PaeoniaWidgetDeepLink(url) {
                    self.widgetDeepLink = widgetDeepLink
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
            // A tapped widget alert routes through the same deep-link path as the
            // Home Screen widget, so the drawing screen opens either way.
            .onChange(of: notificationRouter.pendingWidgetDeepLink) { _, deepLink in
                guard let deepLink else {
                    return
                }

                widgetDeepLink = deepLink
                notificationRouter.consumePendingWidgetDeepLink()
            }
        }
    }
}
