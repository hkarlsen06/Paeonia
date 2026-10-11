import Foundation

/// Caps how long the network part of signing in may take. Clerk and the system
/// wait 60 seconds per stalled request and Clerk retries some of them, so
/// without a cap the sign-in screen can spin for minutes. On timeout the
/// person sees the sign-in failure banner and can try again.
///
/// Sheets where the person picks an account or types a password are never
/// inside a deadline. Optional work such as importing a Google avatar is not
/// either.
nonisolated enum AuthNetworkDeadline {
    /// Clerk sign-in plus the first profile load.
    static let signIn: Duration = .seconds(30)
    /// The profile load at launch. A timeout opens the app with the cached profile.
    static let restore: Duration = .seconds(15)
    /// Signing out a half-finished attempt. A leftover session is signed out
    /// again before the next attempt, so this never needs to wait long.
    static let cleanup: Duration = .seconds(5)

    /// Runs `operation` and throws `URLError(.timedOut)` once `deadline` passes.
    /// The operation is cancelled at that point.
    static func run<Value: Sendable>(
        until deadline: ContinuousClock.Instant,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(until: deadline, clock: .continuous)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw URLError(.timedOut)
            }
            return value
        }
    }

    static func run<Value: Sendable>(
        within limit: Duration,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await run(until: .now + limit, operation)
    }
}
