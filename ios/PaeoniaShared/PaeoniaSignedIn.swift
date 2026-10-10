import Foundation

/// Reports whether a user session exists right now.
typealias PaeoniaSignedInCheck = @Sendable () async -> Bool

/// Local sign-in guard for gateways that carry durable pending operations.
///
/// The backend rejects anonymous writes with a permanent error. Failing here
/// instead keeps the operation pending, so it retries after sign-in is restored.
nonisolated enum PaeoniaSignedIn {
    /// Asks the shared client provider whether a token source can produce a session.
    static let live: PaeoniaSignedInCheck = {
        await PaeoniaConvexClientProvider.shared.isSignedIn()
    }

    static func require(_ isSignedIn: PaeoniaSignedInCheck) async throws {
        guard await isSignedIn() else {
            throw PaeoniaConvexError.notAuthenticated
        }
    }
}
