import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum AppleSignInError: Error, Equatable {
    case alreadyInProgress
    case missingIdentityToken
    case invalidIdentityToken
    case missingPresentationAnchor
}

@MainActor
protocol AppleSignInProviding: AnyObject {
    func signIn() async throws -> AppleSignInCredential
}

@MainActor
final class AppleSignInService: NSObject, AppleSignInProviding {
    private var pendingContinuation: CheckedContinuation<AppleSignInCredential, Error>?
    private var pendingNonce: String?
    private var currentController: ASAuthorizationController?

    func signIn() async throws -> AppleSignInCredential {
        guard pendingContinuation == nil else {
            throw AppleSignInError.alreadyInProgress
        }

        let nonce = Self.randomNonceString()
        pendingNonce = nonce

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            currentController = controller
            controller.performRequests()
        }
    }

    private func finish(with result: Result<AppleSignInCredential, Error>) {
        let continuation = pendingContinuation
        pendingContinuation = nil
        pendingNonce = nil
        currentController = nil

        switch result {
        case let .success(credential):
            continuation?.resume(returning: credential)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

            if status != errSecSuccess {
                fatalError("Unable to generate a secure random nonce.")
            }

            for randomByte in randomBytes where remainingLength > 0 {
                if Int(randomByte) < charset.count {
                    result.append(charset[Int(randomByte)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AppleSignInError.invalidIdentityToken))
            return
        }

        guard let identityToken = appleIDCredential.identityToken else {
            finish(with: .failure(AppleSignInError.missingIdentityToken))
            return
        }

        guard let identityTokenString = String(data: identityToken, encoding: .utf8),
              let nonce = pendingNonce else {
            finish(with: .failure(AppleSignInError.invalidIdentityToken))
            return
        }

        finish(
            with: .success(
                AppleSignInCredential(
                    idToken: identityTokenString,
                    nonce: nonce,
                    fullName: Self.fullName(from: appleIDCredential.fullName)
                )
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: .failure(error))
    }

    private static func fullName(from components: PersonNameComponents?) -> String? {
        guard let components else {
            return nil
        }

        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name.trimmedNonEmpty
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let window = windowScenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            return window
        }

        guard let windowScene = windowScenes.first else {
            fatalError("Sign in with Apple needs an active window scene.")
        }

        return ASPresentationAnchor(windowScene: windowScene)
    }
}
