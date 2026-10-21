import Foundation
import Observation

/// The sign-in methods on the profile screen: which of Apple and Google are
/// linked, and linking or unlinking one. It never leaves the account without a
/// method. The linker refuses to unlink the last one, and the screen hides that
/// action while only one is linked.
@MainActor
@Observable
final class SignInMethodsViewModel {
    enum Notice: Equatable {
        case linked(SignInMethod)
        case unlinked(SignInMethod)
        case linkFailed(Problem, SignInMethod)
        case unlinkFailed(Problem, SignInMethod)
    }

    enum Problem: Equatable {
        case usedByAnotherAccount
        case needsFreshSignIn
        case offline
        case other
    }

    private(set) var linkedMethods: [LinkedSignInMethod]
    /// The method whose link or unlink is running. Only one change runs at a time.
    private(set) var busyMethod: SignInMethod?
    private(set) var notice: Notice?

    private let linker: any SignInMethodLinking
    private let onChanged: @MainActor () async -> Void

    /// `onChanged` runs after a link or unlink went through. The app uses it to
    /// tell the server, which keeps Apple on record for account deletion.
    init(
        linker: any SignInMethodLinking,
        onChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.linker = linker
        self.onChanged = onChanged
        linkedMethods = linker.linkedMethods()
    }

    var isBusy: Bool {
        busyMethod != nil
    }

    /// Unlinking needs a second method that stays.
    var canUnlink: Bool {
        linkedMethods.count > 1
    }

    var unlinkedMethods: [SignInMethod] {
        SignInMethod.allCases.filter { method in
            !linkedMethods.contains { $0.method == method }
        }
    }

    func isLinked(_ method: SignInMethod) -> Bool {
        linkedMethods.contains { $0.method == method }
    }

    /// Shows what the phone knows right away, then what the server says. Offline
    /// the first list stays.
    func refresh() async {
        linkedMethods = linker.linkedMethods()
        guard !isBusy, let fresh = try? await linker.reload(), !isBusy else {
            return
        }
        linkedMethods = fresh
    }

    func link(_ method: SignInMethod) async {
        await change(method) {
            try await linker.link(method)
        } success: {
            .linked(method)
        } failure: {
            .linkFailed($0, method)
        }
    }

    func unlink(_ method: SignInMethod) async {
        await change(method) {
            try await linker.unlink(method)
        } success: {
            .unlinked(method)
        } failure: {
            .unlinkFailed($0, method)
        }
    }

    func consumeNotice() {
        notice = nil
    }

    private func change(
        _ method: SignInMethod,
        _ work: () async throws -> Void,
        success: () -> Notice,
        failure: (Problem) -> Notice
    ) async {
        guard !isBusy else {
            return
        }
        busyMethod = method
        notice = nil
        defer { busyMethod = nil }

        do {
            try await work()
            linkedMethods = linker.linkedMethods()
            notice = success()
            await onChanged()
        } catch SignInMethodLinkError.cancelled {
            // The person closed the sheet. Nothing to tell them.
        } catch {
            notice = failure(Self.problem(for: error))
        }
        // A lost answer can hide a change that went through.
        linkedMethods = linker.linkedMethods()
    }

    private static func problem(for error: any Error) -> Problem {
        switch error as? SignInMethodLinkError {
        case .usedByAnotherAccount:
            .usedByAnotherAccount
        case .needsFreshSignIn:
            .needsFreshSignIn
        case let .failed(failure) where failure == .offline:
            .offline
        case .cancelled, .lastMethod, .failed, nil:
            .other
        }
    }
}

enum SignInMethodsViewModelFactory {
    /// The view model for the signed-in Clerk account. Nil when no one is signed in
    /// through Clerk, which is the case for developer scenarios and previews.
    static func makeDefault() -> SignInMethodsViewModel? {
        guard PaeoniaClerk.currentAccountID() != nil else {
            return nil
        }
        return SignInMethodsViewModel(
            linker: ClerkSignInMethodLinker(),
            // Its own task, so the tries outlive the screen and the spinner does not wait for them.
            onChanged: { Task { await SignInMethodsServerSync.syncAfterChange() } }
        )
    }
}
