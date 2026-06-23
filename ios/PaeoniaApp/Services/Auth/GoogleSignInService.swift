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
    private static let requestTimeout: UInt64 = 120_000_000_000

    private let configResult: Result<GoogleSignInConfig, Error>
    private var activeRequestID: UUID?
    private var continuation: CheckedContinuation<GoogleSignInCredential, Error>?
    private var timeoutTask: Task<Void, Never>?

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
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: Self.requestTimeout)
                    } catch {
                        return
                    }

                    self?.completeRequest(
                        id: requestID,
                        result: .failure(GoogleSignInServiceError.timedOut)
                    )
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
        guard activeRequestID == requestID, let continuation else {
            return
        }

        self.continuation = nil
        activeRequestID = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        continuation.resume(with: result)
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
