import ClerkKit
import Foundation

/// Configures Clerk for the app and the widget extension.
///
/// Both processes use the same keychain service and access group, so the
/// widget reads the session the app created. The publishable key comes from the
/// `PaeoniaClerkPublishableKey` Info.plist entry, which `PAEONIA_CLERK_PUBLISHABLE_KEY`
/// fills in from the xcconfig files.
nonisolated enum PaeoniaClerk {
    static let keychainService = "no.paeonia.clerk"
    static let keychainAccessGroup = "48ZSLD4RMP.no.paeonia.shared"

    @MainActor private static var isConfigured = false

    /// The configured key, or `nil` when the build has no Clerk key yet.
    static func publishableKey(in bundle: Bundle = .main) -> String? {
        guard
            let raw = bundle.object(forInfoDictionaryKey: "PaeoniaClerkPublishableKey") as? String,
            !raw.hasPrefix("$(")
        else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Configures Clerk once and points the Convex client at its session.
    /// Returns `false` when no publishable key is set, so callers can fall back
    /// to the unavailable-auth path instead of touching `Clerk.shared`.
    @MainActor
    @discardableResult
    static func configureIfPossible(bundle: Bundle = .main) -> Bool {
        guard let key = publishableKey(in: bundle) else {
            return false
        }
        guard !isConfigured else {
            return true
        }

        Clerk.configure(
            publishableKey: key,
            options: Clerk.Options(
                keychainConfig: .init(service: keychainService, accessGroup: keychainAccessGroup)
            )
        )
        // Fails locally with `notAuthenticated` when there is no session, so a
        // signed-out device never sends an anonymous request.
        PaeoniaConvexClientProvider.shared.setTokenProvider {
            guard let token = try await Clerk.shared.auth.getToken() else {
                throw PaeoniaConvexError.notAuthenticated
            }
            return token
        }
        PaeoniaConvexClientProvider.shared.setSignedInCheck {
            await currentAccountID() != nil
        }
        isConfigured = true
        return true
    }

    /// The Clerk user id when an active session is stored on this device. It
    /// needs no network call. Returns `nil` before `configureIfPossible()`.
    @MainActor
    static func currentAccountID() -> String? {
        guard isConfigured,
              let session = Clerk.shared.session,
              session.status == .active
        else {
            return nil
        }
        return Clerk.shared.user?.id
    }

    /// The Clerk user id once Clerk has read its saved session, waiting up to
    /// `timeout`. Work started by a launch in the background can run before
    /// Clerk has loaded.
    @MainActor
    static func loadedAccountID(timeout: Duration = .seconds(3)) async -> String? {
        guard isConfigured else {
            return nil
        }
        let deadline = ContinuousClock.now + timeout
        // Clerk has no load callback to await here, so check every 100 ms.
        while !Clerk.shared.isLoaded, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return currentAccountID()
    }
}
