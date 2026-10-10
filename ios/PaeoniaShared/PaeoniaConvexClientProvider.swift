import Foundation

enum PaeoniaConvexConfigError: Error, Equatable {
    case missingURL
    case invalidURL(String)
}

/// Owns the app's single `PaeoniaConvexClient`.
///
/// The deployment URL comes from the `PaeoniaConvexURL` Info.plist key. The auth
/// layer installs the session token source with `setTokenProvider` at launch, so
/// feature gateways never touch Clerk directly.
nonisolated final class PaeoniaConvexClientProvider: Sendable {
    static let shared = PaeoniaConvexClientProvider()

    private let tokenSource = TokenSource()
    private let clientResult: Result<PaeoniaConvexClient, Error>

    init(bundle: Bundle = .main) {
        let tokenSource = tokenSource
        clientResult = Result {
            PaeoniaConvexClient(deploymentURL: try Self.deploymentURL(in: bundle)) {
                try await tokenSource.token()
            }
        }
    }

    func client() throws -> PaeoniaConvexClient {
        try clientResult.get()
    }

    func setTokenProvider(_ provider: @escaping PaeoniaConvexClient.TokenProvider) {
        tokenSource.set(provider)
    }

    /// Installs a local check for "a user session exists". Without one,
    /// `isSignedIn()` falls back to asking the token provider for a token.
    func setSignedInCheck(_ check: @escaping @Sendable () async -> Bool) {
        tokenSource.setSignedInCheck(check)
    }

    func isSignedIn() async -> Bool {
        await tokenSource.isSignedIn()
    }

    static func deploymentURL(in bundle: Bundle) throws -> URL {
        guard
            let raw = bundle.object(forInfoDictionaryKey: "PaeoniaConvexURL") as? String,
            !raw.hasPrefix("$("),
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw PaeoniaConvexConfigError.missingURL
        }
        guard let url = URL(string: raw), url.scheme != nil, url.host() != nil else {
            throw PaeoniaConvexConfigError.invalidURL(raw)
        }
        return url
    }

    private final class TokenSource: @unchecked Sendable {
        private let lock = NSLock()
        private var provider: PaeoniaConvexClient.TokenProvider = { nil }
        private var signedInCheck: (@Sendable () async -> Bool)?

        func set(_ provider: @escaping PaeoniaConvexClient.TokenProvider) {
            lock.withLock { self.provider = provider }
        }

        func setSignedInCheck(_ check: @escaping @Sendable () async -> Bool) {
            lock.withLock { signedInCheck = check }
        }

        func isSignedIn() async -> Bool {
            if let check = lock.withLock({ signedInCheck }) {
                return await check()
            }
            return (try? await token()) != nil
        }

        func token() async throws -> String? {
            let provider = lock.withLock { self.provider }
            return try await provider()
        }
    }
}
