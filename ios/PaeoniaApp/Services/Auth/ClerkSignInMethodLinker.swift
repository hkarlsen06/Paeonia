import AuthenticationServices
import ClerkKit
import Foundation

/// Links Apple and Google through Clerk's external accounts.
///
/// Apple uses the same sheet and nonce as signing in (`AppleSignInService`), then
/// hands Clerk the identity token. Google opens Clerk's web sheet, like signing in.
/// Both need the person to be signed in already, so the new method joins this
/// account instead of starting a second one.
@MainActor
final class ClerkSignInMethodLinker: SignInMethodLinking {
    private let appleSignIn: any AppleSignInProviding

    init(appleSignIn: any AppleSignInProviding = AppleSignInService()) {
        self.appleSignIn = appleSignIn
    }

    func linkedMethods() -> [LinkedSignInMethod] {
        guard let user = Clerk.shared.user else {
            return []
        }
        return Self.linkedMethods(in: user.verifiedExternalAccounts)
    }

    func reload() async throws -> [LinkedSignInMethod] {
        do {
            try await Clerk.shared.refreshClient()
        } catch {
            throw Self.classify(error)
        }
        return linkedMethods()
    }

    func link(_ method: SignInMethod) async throws {
        guard let user = Clerk.shared.user else {
            throw SignInMethodLinkError.failed(.other)
        }

        do {
            switch method {
            case .apple:
                let credential = try await appleSignIn.signIn()
                let account = try await user.createExternalAccount(
                    provider: .apple,
                    idToken: credential.idToken
                )
                try Self.requireVerified(account)
            case .google:
                // Clerk adds the account unverified. The web sheet verifies it.
                let pending = try await user.createExternalAccount(provider: .google)
                do {
                    try Self.requireVerified(try await pending.reauthorize())
                } catch {
                    // A half-made link would only clutter the account.
                    _ = try? await pending.destroy()
                    throw error
                }
            }
        } catch {
            throw Self.classify(error)
        }
    }

    func unlink(_ method: SignInMethod) async throws {
        guard let user = Clerk.shared.user else {
            throw SignInMethodLinkError.failed(.other)
        }
        guard linkedMethods().contains(where: { $0.method != method }) else {
            throw SignInMethodLinkError.lastMethod
        }

        do {
            // Includes links that never finished verifying.
            for account in user.externalAccounts where SignInMethod(clerkProvider: account.provider) == method {
                try await account.destroy()
            }
        } catch {
            throw Self.classify(error)
        }
    }

    /// Whether Apple is linked, after a short refresh from the server. Account
    /// deletion uses it to ask for Apple's authorization code, which the server
    /// needs to revoke Sign in with Apple, also when the person signed in with Google.
    static func appleIsLinked() async -> Bool {
        _ = try? await AuthNetworkDeadline.run(within: AuthNetworkDeadline.cleanup) { @MainActor in
            _ = try await Clerk.shared.refreshClient()
        }
        return Clerk.shared.user?.verifiedExternalAccounts
            .contains { SignInMethod(clerkProvider: $0.provider) == .apple } ?? false
    }

    // MARK: - Pure rules

    nonisolated static func linkedMethods(in accounts: [ExternalAccount]) -> [LinkedSignInMethod] {
        var seen = Set<SignInMethod>()
        var linked: [LinkedSignInMethod] = []
        for account in accounts {
            guard let method = SignInMethod(clerkProvider: account.provider), seen.insert(method).inserted else {
                continue
            }
            linked.append(LinkedSignInMethod(method: method, email: account.emailAddress))
        }
        // The same order on every screen: Apple, then Google.
        return linked.sorted { $0.method.sortOrder < $1.method.sortOrder }
    }

    /// Clerk error codes that mean the provider's account belongs to someone else.
    private nonisolated static let usedElsewhereCodes: Set<String> = [
        "external_account_exists",
        "form_identifier_exists",
        "identification_claimed",
    ]

    /// Turns whatever Apple, the web sheet, Clerk or the network threw into the
    /// few cases the screen has words for.
    nonisolated static func classify(_ error: any Error) -> SignInMethodLinkError {
        if let known = error as? SignInMethodLinkError {
            return known
        }
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return .cancelled
        }
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return .cancelled
        }
        if let apiError = error as? ClerkAPIError {
            if usedElsewhereCodes.contains(apiError.code) {
                return .usedByAnotherAccount
            }
            if apiError.code.contains("reverification") {
                return .needsFreshSignIn
            }
        }
        return .failed(PaeoniaFailure(error))
    }

    /// Throws what Clerk recorded when the link did not end up verified.
    private static func requireVerified(_ account: ExternalAccount) throws {
        guard account.verification?.status == .verified else {
            if let recorded = account.verification?.error {
                throw recorded
            }
            throw SignInMethodLinkError.failed(.other)
        }
    }
}

private extension SignInMethod {
    nonisolated var sortOrder: Int {
        switch self {
        case .apple: 0
        case .google: 1
        }
    }
}
