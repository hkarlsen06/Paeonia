import ClerkKit
import Foundation

/// The Clerk calls behind `LiveAuthGateway`'s sign-in and sign-out.
extension LiveAuthGateway {
    @MainActor
    static func signInWithClerk<Result>(
        fallbackProvider: AuthProvider,
        _ signIn: () async throws -> Result
    ) async throws -> RemoteAuthSession {
        await signOutLeftoverSession()
        _ = try await signIn()
        // A flow that needs more steps leaves no active session behind.
        guard let session = activeClerkSession(fallbackProvider: fallbackProvider) else {
            throw AuthServiceError.noActiveSession
        }
        return session
    }

    /// The app only starts a sign-in while signed out. A session left over
    /// from an earlier failed attempt would make Clerk refuse the new one.
    @MainActor
    static func signOutLeftoverSession() async {
        guard Clerk.shared.session != nil else {
            return
        }
        // Bounded, so a stalled connection cannot hold up the sign-in sheet.
        _ = try? await AuthNetworkDeadline.run(within: AuthNetworkDeadline.cleanup) { @MainActor in
            try await Clerk.shared.auth.signOut()
        }
    }

    /// Emails a code to a returning address, or starts an account for a new one.
    @MainActor
    static func startEmailCode(to emailAddress: String) async throws -> PendingEmailCode {
        await signOutLeftoverSession()
        do {
            return .signIn(try await Clerk.shared.auth.signInWithEmailCode(emailAddress: emailAddress))
        } catch let error as ClerkAPIError where error.code == "form_identifier_not_found" {
            let signUp = try await Clerk.shared.auth.signUp(emailAddress: emailAddress)
            guard signUp.status == .complete else {
                return .signUp(try await signUp.sendEmailCode())
            }
            // A Clerk instance that skips email verification at sign-up has
            // already signed the new account in. Nobody gets in without proving
            // the address, so sign out and send a code like for a returning one.
            try await Clerk.shared.auth.signOut()
            return .signIn(try await Clerk.shared.auth.signInWithEmailCode(emailAddress: emailAddress))
        }
    }

    /// The email sheet's words for a Clerk refusal. Anything else comes back
    /// unchanged.
    nonisolated static func emailSignInError(from error: any Error) -> any Error {
        guard let apiError = error as? ClerkAPIError else {
            return error
        }
        switch apiError.code {
        case "form_param_format_invalid":
            return EmailSignInError.invalidEmail
        case "form_code_incorrect":
            return EmailSignInError.wrongCode
        case "verification_expired", "verification_failed":
            return EmailSignInError.codeExpired
        case "too_many_requests":
            return EmailSignInError.tooManyTries
        default:
            return error
        }
    }

    @MainActor
    static func signOutOfClerk() async throws {
        try await Clerk.shared.auth.signOut()
    }

    @MainActor
    static func clerkSessionIsGone() async -> Bool {
        _ = try? await Clerk.shared.refreshClient()
        return Clerk.shared.session == nil
    }

    /// The cached Clerk session. It needs no network, so the app can restore
    /// the signed-in user while offline.
    @MainActor
    static func activeClerkSession(
        fallbackProvider: AuthProvider = .unknown
    ) -> RemoteAuthSession? {
        let clerk = Clerk.shared
        guard let session = clerk.session, session.status == .active, let user = clerk.user else {
            return nil
        }

        let account = user.externalAccounts.first { provider(of: $0) != .unknown }
        return RemoteAuthSession(
            accountID: user.id,
            provider: account.map(provider(of:)) ?? fallbackProvider,
            displayName: (user.firstName ?? account?.firstName)?.trimmedNonEmpty,
            providerAvatarURL: account?.imageUrl.flatMap(URL.init(string:))
        )
    }

    static func provider(of account: ExternalAccount) -> AuthProvider {
        let name = account.provider.lowercased()
        if name.contains("apple") {
            return .apple
        }
        if name.contains("google") {
            return .google
        }
        return .unknown
    }
}
