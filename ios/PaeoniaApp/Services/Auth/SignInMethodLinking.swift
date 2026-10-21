import Foundation

/// A way to sign in to Paeonia. One account can have both linked, and either one
/// then opens the same account.
nonisolated enum SignInMethod: String, CaseIterable, Identifiable, Sendable {
    case apple
    case google

    var id: String { rawValue }

    /// The method for a Clerk provider name such as `oauth_apple` or `google`.
    init?(clerkProvider: String) {
        let name = clerkProvider.lowercased()
        if name.contains("apple") {
            self = .apple
        } else if name.contains("google") {
            self = .google
        } else {
            return nil
        }
    }
}

/// A sign-in method that is linked to the account right now.
nonisolated struct LinkedSignInMethod: Equatable, Identifiable, Sendable {
    let method: SignInMethod
    /// The email the provider gave Clerk. Apple's hidden address is dropped,
    /// because it only confuses.
    let email: String?

    var id: SignInMethod { method }

    init(method: SignInMethod, email: String?) {
        self.method = method
        let trimmed = email?.trimmedNonEmpty
        self.email = trimmed?.lowercased().hasSuffix("@privaterelay.appleid.com") == true ? nil : trimmed
    }
}

/// Why linking or unlinking did not happen. Cancelling a provider sheet is its
/// own case, because the screen shows nothing for it.
nonisolated enum SignInMethodLinkError: Error, Equatable, Sendable {
    /// The person closed the Apple or Google sheet.
    case cancelled
    /// The provider's account already belongs to another Paeonia account.
    case usedByAnotherAccount
    /// Clerk wants the person to have signed in recently before this change.
    case needsFreshSignIn
    /// The method is the only one left, so it cannot be unlinked.
    case lastMethod
    case failed(PaeoniaFailure)
}

/// Links and unlinks Apple and Google on the signed-in account.
@MainActor
protocol SignInMethodLinking: AnyObject {
    /// The linked methods as this phone knows them. Needs no network call.
    func linkedMethods() -> [LinkedSignInMethod]
    /// Asks the server for the current list and returns it.
    func reload() async throws -> [LinkedSignInMethod]
    func link(_ method: SignInMethod) async throws
    /// Fails with `lastMethod` when no other method would stay linked.
    func unlink(_ method: SignInMethod) async throws
}
