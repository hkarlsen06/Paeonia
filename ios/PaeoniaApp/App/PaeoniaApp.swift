import GoogleSignIn
import SwiftUI

@main
struct PaeoniaApp: App {
  @UIApplicationDelegateAdaptor(PaeoniaAppDelegate.self) private var appDelegate
  @State private var widgetDeepLink: PaeoniaWidgetDeepLink?

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
    }
  }
}
