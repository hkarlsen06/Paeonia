import ClerkKit
import Foundation

extension LiveAuthGateway {
    /// Clerk reads its saved sign-in from the keychain once, when it is configured.
    /// A launch before the first unlock after a restart cannot read it, and Clerk
    /// reads it again only on its next request or after the app comes to the
    /// foreground, which can land after the first screen asks. A request makes it
    /// read the keychain first, so the saved sign-in counts even offline.
    @MainActor
    static func loadClerkSessionLockedAtLaunch() async {
        guard Clerk.shared.client == nil, ClerkKeychainState.current() == .stored else {
            return
        }
        _ = try? await Clerk.shared.refreshClient()
    }
}
