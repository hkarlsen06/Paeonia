import GoogleSignIn
import SwiftUI

@main
struct PaeoniaApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .onOpenURL { url in
          if GIDSignIn.sharedInstance.handle(url) {
            return
          }

          PaeoniaSupabaseClientProvider.shared.handle(url)
        }
    }
  }
}
