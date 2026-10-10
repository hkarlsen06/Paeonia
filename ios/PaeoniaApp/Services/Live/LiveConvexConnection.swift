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
            if isAuthenticated {
                return client
            }
            // The provider logs in on Clerk session changes. This covers a cold
            // launch where a stored session exists and no change event follows.
            let loginAllowed = nextLoginAttemptAt.map { ContinuousClock.now >= $0 } ?? true
            if !isLoggingIn, loginAllowed, PaeoniaClerk.currentAccountID() != nil, Clerk.shared.isLoaded {
                isLoggingIn = true
                let result = await client.loginFromCache()
                isLoggingIn = false
                if case .failure = result {
                    // Offline or the token service is down. Wait instead of retrying at once.
                    nextLoginAttemptAt = ContinuousClock.now + loginBackoff.nextDelay()
                } else {
                    loginBackoff.reset()
                    nextLoginAttemptAt = nil
                }
                continue
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
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
                        self?.isAuthenticated = true
                    } else {
                        self?.isAuthenticated = false
                    }
                }
            },
        ]
        return client
    }
}
