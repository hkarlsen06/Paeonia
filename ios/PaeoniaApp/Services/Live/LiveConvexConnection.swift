import Combine
@preconcurrency import ConvexMobile
import ClerkConvex
import ClerkKit
import Foundation
import Observation

/// Where the live socket stands. Safe to show as a subtle "connecting" hint.
nonisolated enum LiveConnectionState: Equatable, Sendable {
    /// No client yet: nothing has subscribed, or the build has no Convex URL or Clerk key.
    case idle
    case connecting
    case connected
}

/// Delay between failed cache logins: 1 s, doubling to a 30 s cap, back to 1 s after a success.
nonisolated struct LiveLoginBackoff: Sendable {
    private(set) var delay: Duration = .seconds(1)

    mutating func nextDelay() -> Duration {
        defer { delay = min(delay * 2, .seconds(30)) }
        return delay
    }

    mutating func reset() {
        delay = .seconds(1)
    }
}

/// Owns the one `ConvexClientWithAuth` used for live subscriptions.
///
/// The client is created on first use, after `PaeoniaClerk.configureIfPossible()`
/// ran, and follows the Clerk session through `ClerkConvexAuthProvider`.
/// Never call `logout()` on it. The provider's `logout()` signs out of Clerk.
/// Sign out through Clerk and the client follows.
/// Writes and one-shot reads keep using `PaeoniaConvexClient`.
@MainActor
@Observable
final class LiveConvexConnection {
    static let shared = LiveConvexConnection()

    private(set) var connectionState: LiveConnectionState = .idle
    private(set) var isAuthenticated = false

    @ObservationIgnored private var client: ConvexClientWithAuth<String>?
    /// The Clerk user the client last logged in as. The auth provider's logout
    /// signs out of Clerk a second time and skips clearing the socket's token
    /// when that call fails, so the client can stay logged in as the previous
    /// person after an account switch.
    @ObservationIgnored private var authenticatedAccountID: String?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    @ObservationIgnored private var isLoggingIn = false
    // Shared by every waiting feed, so seven subscriptions make one login attempt per delay.
    @ObservationIgnored private var loginBackoff = LiveLoginBackoff()
    @ObservationIgnored private var nextLoginAttemptAt: ContinuousClock.Instant?
    @ObservationIgnored private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Returns the client once Convex accepts the Clerk session, or `nil` when
    /// live data is not configured or the task is cancelled. Waits while signed out.
    func authenticatedClient() async -> ConvexClientWithAuth<String>? {
        guard let client = makeClientIfNeeded() else {
            return nil
        }

        while !Task.isCancelled {
            let accountID = PaeoniaClerk.currentAccountID()
            if Self.isLoggedIn(
                as: accountID,
                isAuthenticated: isAuthenticated,
                authenticatedAccountID: authenticatedAccountID
            ) {
                return client
            }
            // The provider logs in on Clerk session changes. This covers a cold
            // launch where a stored session exists and no change event follows,
            // and a socket still logged in as the previous account.
            let loginAllowed = nextLoginAttemptAt.map { ContinuousClock.now >= $0 } ?? true
            if !isLoggingIn, loginAllowed, accountID != nil, Clerk.shared.isLoaded {
                isLoggingIn = true
                let result = await client.loginFromCache()
                isLoggingIn = false
                if case .failure = result {
                    // Offline or the token service is down. Wait instead of retrying at once.
                    nextLoginAttemptAt = ContinuousClock.now + loginBackoff.nextDelay()
                } else {
                    loginBackoff.reset()
                    nextLoginAttemptAt = nil
                    authenticatedAccountID = accountID
                    isAuthenticated = true
                }
                continue
            }
            try? await Task.sleep(for: Self.wait(untilNextLoginAt: nextLoginAttemptAt, now: .now))
        }
        return nil
    }

    /// How long a waiting feed sleeps before it checks again. During a failed-login
    /// backoff (offline, up to 30 seconds) nothing can change before the next
    /// attempt, so every feed sleeps until then instead of waking twice a second.
    nonisolated static func wait(
        untilNextLoginAt nextLoginAttemptAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> Duration {
        let poll = Duration.milliseconds(500)
        guard let nextLoginAttemptAt else {
            return poll
        }
        return max(nextLoginAttemptAt - now, poll)
    }

    /// Subscriptions may only use the socket when it is logged in as the person
    /// signed in to Clerk right now. Otherwise results for one account would be
    /// stored under another.
    nonisolated static func isLoggedIn(
        as accountID: String?,
        isAuthenticated: Bool,
        authenticatedAccountID: String?
    ) -> Bool {
        isAuthenticated && accountID != nil && authenticatedAccountID == accountID
    }

    private func makeClientIfNeeded() -> ConvexClientWithAuth<String>? {
        if let client {
            return client
        }
        guard PaeoniaClerk.configureIfPossible(bundle: bundle),
              let url = try? PaeoniaConvexClientProvider.deploymentURL(in: bundle)
        else {
            return nil
        }

        let client = ConvexClientWithAuth(
            deploymentUrl: url.absoluteString,
            authProvider: ClerkConvexAuthProvider()
        )
        self.client = client
        connectionState = .connecting
        observers = [
            Task { [weak self] in
                for await state in client.watchWebSocketState().values {
                    self?.connectionState = state == .connected ? .connected : .connecting
                }
            },
            Task { [weak self] in
                for await state in client.authState.values {
                    if case .authenticated = state {
                        self?.authenticatedAccountID = PaeoniaClerk.currentAccountID()
                        self?.isAuthenticated = true
                    } else {
                        self?.authenticatedAccountID = nil
                        self?.isAuthenticated = false
                    }
                }
            },
        ]
        return client
    }
}
