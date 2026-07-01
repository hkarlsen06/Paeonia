import Foundation
import GoogleSignIn
import UIKit

struct GoogleSignInCredential: Equatable, Sendable {
    let idToken: String
    let accessToken: String?
}

enum GoogleSignInServiceError: Error, Equatable {
    case missingClientID
    case noPresenter
    case noResult
    case noIDToken
    case requestInProgress
    case timedOut
    case userCancelled
    case failed(String)
}

@MainActor
protocol GoogleSignInProviding: AnyObject {
    func signIn() async throws -> GoogleSignInCredential
}

@MainActor
final class GoogleSignInService: GoogleSignInProviding {
    /// Shared production instance. Sign-in state (a result that lands after our
    /// backstop already gave up) must outlive a single `RootView` rebuild, so the
    /// app uses one long-lived service instead of recreating it per render. Tests
    /// inject their own `GoogleSignInProviding` double.
    static let shared = GoogleSignInService()

    private static let requestTimeout: UInt64 = 120_000_000_000
    /// How long a late credential stays usable for the next sign-in attempt.
    /// Google ID tokens live far longer; this only bounds how stale a "you just
    /// authenticated" hand-off can be before we fall back to a fresh flow.
    private static let lateCredentialFreshness: TimeInterval = 120

    private let configResult: Result<GoogleSignInConfig, Error>
    private var activeRequestID: UUID?
    private var continuation: CheckedContinuation<GoogleSignInCredential, Error>?
    private var timeoutTask: Task<Void, Never>?
    /// The most recent request whose caller our backstop already unblocked. Kept
    /// so the real Google result that lands afterwards is recognised instead of
    /// dropped on a `nil` continuation.
    private var timedOutRequestID: UUID?
    /// A real success that arrived after its caller timed out. Delivered to the
    /// next sign-in attempt so the user ends up signed in rather than seeing a
    /// false failure.
    private var bufferedCredential: BufferedCredential?

    private struct BufferedCredential {
        let credential: GoogleSignInCredential
        let capturedAt: Date
    }

    init(bundle: Bundle = .main) {
        configResult = Result {
            try GoogleSignInConfig(bundle: bundle)
        }

        if case let .success(config) = configResult {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: config.iosClientID
            )
        }
    }

    func signIn() async throws -> GoogleSignInCredential {
        let config = try configResult.get()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: config.iosClientID
        )

        // A previous attempt may have timed out from the caller's perspective but
        // still completed for real moments later. Hand that credential to this
        // retry instead of opening Google again, so the user signs straight in.
        if let credential = consumeBufferedCredential() {
            return credential
        }

        guard let viewController = Self.topViewController() else {
            throw GoogleSignInServiceError.noPresenter
        }

        return try await performRequest { [weak self] requestID in
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                Task { @MainActor in
                    self?.completeRequest(
                        id: requestID,
                        result: Self.signInResult(result: result, error: error)
                    )
                }
            }
        }
    }

    private static func signInResult(
        result: GIDSignInResult?,
        error: Error?
    ) -> Result<GoogleSignInCredential, Error> {
        if let error {
            let nsError = error as NSError
            // GoogleSignIn uses -5 for user-cancelled flows.
            if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
                return .failure(GoogleSignInServiceError.userCancelled)
            }

            return .failure(GoogleSignInServiceError.failed(error.localizedDescription))
        }

        guard let result else {
            return .failure(GoogleSignInServiceError.noResult)
        }

        guard let idToken = result.user.idToken?.tokenString else {
            return .failure(GoogleSignInServiceError.noIDToken)
        }

        return .success(
            GoogleSignInCredential(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
        )
    }

    private func performRequest(
        start: @escaping (UUID) -> Void
    ) async throws -> GoogleSignInCredential {
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard self.continuation == nil else {
                    continuation.resume(
                        throwing: GoogleSignInServiceError.requestInProgress
                    )
                    return
                }

                self.continuation = continuation
                activeRequestID = requestID
                // Starting a fresh attempt supersedes any earlier timed-out one,
                // so its late result should no longer be buffered for delivery.
                timedOutRequestID = nil
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: Self.requestTimeout)
                    } catch {
                        return
                    }

                    self?.handleTimeout(id: requestID)
                }

                start(requestID)
            }
        } onCancel: { [self] in
            Task { @MainActor in
                completeRequest(
                    id: requestID,
                    result: .failure(GoogleSignInServiceError.userCancelled)
                )
            }
        }
    }

    private func completeRequest(
        id requestID: UUID,
        result: Result<GoogleSignInCredential, Error>
    ) {
        if activeRequestID == requestID, let continuation {
            self.continuation = nil
            activeRequestID = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            timedOutRequestID = nil

            continuation.resume(with: result)
            return
        }

        // The caller already timed out. Keep a real success so the next attempt
        // can use it; a late failure or cancel just clears the pending marker.
        guard timedOutRequestID == requestID else {
            return
        }

        timedOutRequestID = nil
        if case let .success(credential) = result {
            bufferedCredential = BufferedCredential(
                credential: credential,
                capturedAt: Date()
            )
        }
    }

    /// Hands control back to the caller after the backstop expires, but remembers
    /// this request so its real result is preserved rather than discarded.
    private func handleTimeout(id requestID: UUID) {
        guard activeRequestID == requestID, let continuation else {
            return
        }

        self.continuation = nil
        activeRequestID = nil
        timeoutTask = nil
        timedOutRequestID = requestID

        continuation.resume(throwing: GoogleSignInServiceError.timedOut)
    }

    /// Returns and clears a buffered late credential when it is still fresh enough
    /// to reuse. A stale buffer is dropped so the caller falls back to a normal
    /// sign-in flow.
    private func consumeBufferedCredential() -> GoogleSignInCredential? {
        guard let buffered = bufferedCredential else {
            return nil
        }

        bufferedCredential = nil
        guard Date().timeIntervalSince(buffered.capturedAt) <= Self.lateCredentialFreshness else {
            return nil
        }

        return buffered.credential
    }

    private static func topViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?
                .rootViewController
        else {
            return nil
        }

        return topViewController(from: rootViewController)
    }

    private static func topViewController(
        from viewController: UIViewController
    ) -> UIViewController {
        if let presentedViewController = viewController.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        if let navigationController = viewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return topViewController(from: visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return topViewController(from: selectedViewController)
        }

        return viewController
    }
}

private struct GoogleSignInConfig {
    let iosClientID: String

    init(bundle: Bundle) throws {
        guard
            let rawValue = bundle.object(forInfoDictionaryKey: "PaeoniaGoogleIOSClientID") as? String,
            let iosClientID = rawValue.nilIfPlaceholder?.nilIfBlank
        else {
            throw GoogleSignInServiceError.missingClientID
        }

        self.iosClientID = iosClientID
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var nilIfPlaceholder: String? {
        hasPrefix("$(") ? nil : self
    }
}
