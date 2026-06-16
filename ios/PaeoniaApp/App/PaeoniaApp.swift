import SwiftUI

@main
struct PaeoniaApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .onOpenURL { url in
          PaeoniaSupabaseClientProvider.shared.handle(url)
        }
    }
  }
}
