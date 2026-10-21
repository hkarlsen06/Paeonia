import Foundation
import LocalAuthentication

/// Asks the phone whether its owner is here. The tests replace it.
protocol AppLockAuthenticating {
    func capability() -> AppLockCapability
    func authenticate(reason: String) async -> AppLockAuthResult
}

/// Face ID or Touch ID, with the phone's passcode as the fallback the system
/// offers itself. `.deviceOwnerAuthentication` is why a failed or locked-out
/// face never leaves anyone stuck outside their own app.
struct LocalAuthenticationAppLockAuthenticator: AppLockAuthenticating {
    func capability() -> AppLockCapability {
        var error: NSError?
        let canAuthenticate = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return AppLockCapability(biometry: biometry(), canAuthenticate: canAuthenticate)
    }

    func authenticate(reason: String) async -> AppLockAuthResult {
        // A fresh context each time, so an earlier success is never reused.
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }

        do {
            let succeeded = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return succeeded ? .success : .failed
        } catch let error as LAError {
            return Self.result(for: error.code)
        } catch {
            return .failed
        }
    }

    /// The type is only filled in after a check, and it is the biometric policy
    /// that fills it in. A phone with Face ID that has no face set up still
    /// reports Face ID, and the system then offers the passcode in its place.
    private func biometry() -> AppLockBiometry {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    nonisolated static func result(for code: LAError.Code) -> AppLockAuthResult {
        switch code {
        case .userCancel, .appCancel, .systemCancel, .notInteractive:
            .cancelled
        case .passcodeNotSet:
            .unavailable
        default:
            .failed
        }
    }
}
