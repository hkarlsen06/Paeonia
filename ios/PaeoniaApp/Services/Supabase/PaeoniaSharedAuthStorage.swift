import Foundation
import Supabase

/// Stores the Supabase session in a keychain access group shared with the
/// widget extension. The legacy store remains a migration fallback so updating
/// Paeonia does not sign existing users out.
nonisolated struct PaeoniaSharedAuthStorage: AuthLocalStorage {
    static let accessGroup = "48ZSLD4RMP.no.paeonia.shared"

    private let sharedStorage = KeychainLocalStorage(
        service: "supabase.gotrue.swift",
        accessGroup: accessGroup
    )
    private let legacyStorage = KeychainLocalStorage()

    func store(key: String, value: Data) throws {
        try sharedStorage.store(key: key, value: value)
        // Keep the app's previous store current during the migration window.
        try? legacyStorage.store(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        if let sharedValue = try sharedStorage.retrieve(key: key) {
            return sharedValue
        }

        guard let legacyValue = try legacyStorage.retrieve(key: key) else {
            return nil
        }
        try sharedStorage.store(key: key, value: legacyValue)
        return legacyValue
    }

    func remove(key: String) throws {
        try sharedStorage.remove(key: key)
        try? legacyStorage.remove(key: key)
    }
}
