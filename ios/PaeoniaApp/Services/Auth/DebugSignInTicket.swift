#if DEBUG
import ClerkKit
import Foundation

/// Signs a Debug build into a test account with a Clerk sign-in token, so an
/// agent can sign a simulator in without Apple or Google. `scripts/sim-sign-in`
/// mints the token and launches the app with it in the environment. A phone
/// that is already signed in ignores it, and Release builds don't have it.
enum DebugSignInTicket {
    static let environmentKey = "PAEONIA_DEBUG_SIGN_IN_TICKET"

    @MainActor
    static func signInIfGiven(environment: [String: String] = ProcessInfo.processInfo.environment) async {
        guard let ticket = environment[environmentKey], !ticket.isEmpty,
              await PaeoniaClerk.loadedAccountID() == nil
        else {
            return
        }
        // A failed sign-in leaves the phone signed out, which the sign-in screen shows.
        _ = try? await Clerk.shared.auth.signInWithTicket(ticket)
    }
}
#endif
