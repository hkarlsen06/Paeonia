import GoogleSignIn
import SwiftUI

@main
struct PaeoniaApp: App {
  @UIApplicationDelegateAdaptor(PaeoniaAppDelegate.self) private var appDelegate
  @State private var widgetDeepLink: PaeoniaWidgetDeepLink?
  @State private var notificationRouter = PaeoniaNotificationRouter.shared

  var body: some Scene {
    WindowGroup {
      RootView(widgetDeepLink: $widgetDeepLink)
        .onOpenURL { url in
          if GIDSignIn.sharedInstance.handle(url) {
            return
          }

          if let widgetDeepLink = PaeoniaWidgetDeepLink(url) {
            self.widgetDeepLink = widgetDeepLink
            return
          }

          // TODO: Handle paeonia.no/join/{code} links by saving the invite code
          // in the background, then prefill and reveal the paywall invite field
          // when the user reaches the paywall.
          PaeoniaSupabaseClientProvider.shared.handle(url)
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
