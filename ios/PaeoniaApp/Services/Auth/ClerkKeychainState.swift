import Foundation
import Security

/// Whether the sign-in Clerk keeps in the keychain can be read right now.
///
/// Clerk saves it with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. iOS can
/// launch the app in the background before the first unlock after a restart, for a
/// significant move or a push, and every read fails until then. Clerk then holds no
/// session, which looks the same as being signed out.
nonisolated enum ClerkKeychainState: Equatable {
    /// The phone has not been unlocked since it restarted.
    case locked
    /// Nobody has signed in on this phone.
    case empty
    /// Clerk has stored a sign-in, which may or may not still be active.
    case stored

    /// Reads the item Clerk loads its sign-in from when it is configured
    /// (`ClerkKeychainKey.clerkDeviceToken` in clerk-ios).
    static func current() -> ClerkKeychainState {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: PaeoniaClerk.keychainService,
            kSecAttrAccessGroup as String: PaeoniaClerk.keychainAccessGroup,
            kSecAttrAccount as String: "clerkDeviceToken",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecInteractionNotAllowed:
            return .locked
        case errSecSuccess:
            return .stored
        default:
            return .empty
        }
    }
}
