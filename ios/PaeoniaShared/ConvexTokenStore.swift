import Foundation
import Security
import Synchronization

/// The last token from Clerk's `convex` template, kept in the keychain with the
/// Clerk session it belongs to. Clerk keeps template tokens in memory only, so
/// without this every launch fetched a new one first, and on a phone that took
/// 260 to 410 ms with every launch call waiting on it. A launch within the
/// token's 15 minutes now skips that fetch.
///
/// The app and its extensions share the item through Clerk's access group. It is
/// readable after the first unlock, like Clerk's own session.
nonisolated enum ConvexTokenStore {
    private struct Entry: Codable, Equatable {
        let sessionID: String
        let token: String
    }

    private static let service = "no.paeonia.convex-token"
    private static let account = "convex"
    /// The keychain is read once per process. Later reads and every save go through this copy.
    private static let memory = Mutex<Entry??>(nil)

    /// The saved token for `sessionID` while more than `minimumLifetime` seconds of it are left.
    static func token(sessionID: String, minimumLifetime: TimeInterval, now: Date = .now) -> String? {
        guard let entry = currentEntry(),
              entry.sessionID == sessionID,
              let expiresAt = ConvexTokenSchedule.expiry(ofJWT: entry.token),
              expiresAt.timeIntervalSince(now) > minimumLifetime
        else {
            return nil
        }
        return entry.token
    }

    static func save(_ token: String, sessionID: String) {
        let entry = Entry(sessionID: sessionID, token: token)
        let changed = memory.withLock { cached in
            defer { cached = .some(entry) }
            return cached != .some(entry)
        }
        guard changed, let data = try? JSONEncoder().encode(entry) else {
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    /// Called when the account leaves this phone, so the next person never sends with it.
    static func clear() {
        memory.withLock { $0 = .some(nil) }
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static func currentEntry() -> Entry? {
        if let cached = memory.withLock({ $0 }) {
            return cached
        }
        let entry = readKeychain()
        // A locked phone reads nothing. Keep asking until a read succeeds.
        if entry != nil {
            memory.withLock { $0 = .some(entry) }
        }
        return entry
    }

    private static func readKeychain() -> Entry? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: PaeoniaClerk.keychainAccessGroup,
        ]
    }
}
