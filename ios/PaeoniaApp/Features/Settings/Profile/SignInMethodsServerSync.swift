import Foundation

/// Keeps the server's note of the linked sign-in methods in step with Clerk. The server needs it to
/// know that Apple is linked when the person deletes their account. A link or unlink that the
/// server did not hear about is remembered on the phone and sent again the next time the app opens.
@MainActor
enum SignInMethodsServerSync {
    private static let pendingAccountKey = "signInMethodsSyncPendingAccountID"
    /// Waits between the tries right after a change. The first try goes out at once.
    private static let retryDelays: [Duration] = [.seconds(2), .seconds(8)]

    /// After a link or unlink: remembers that the server has not heard yet, then tries a few times.
    /// When every try fails, the note stays for `retryIfPending`.
    static func syncAfterChange(defaults: UserDefaults = .standard) async {
        guard let accountID = PaeoniaClerk.currentAccountID() else {
            return
        }
        defaults.set(accountID, forKey: pendingAccountKey)
        await attempt(accountID: accountID, delays: retryDelays, defaults: defaults)
    }

    /// Sends a change that no earlier try could deliver. Does nothing when there is none.
    static func retryIfPending(defaults: UserDefaults = .standard) async {
        guard let accountID = PaeoniaClerk.currentAccountID(),
              let pendingAccountID = defaults.string(forKey: pendingAccountKey)
        else {
            return
        }
        guard pendingAccountID == accountID else {
            // The note belongs to someone who signed out.
            defaults.removeObject(forKey: pendingAccountKey)
            return
        }
        await attempt(accountID: accountID, delays: [], defaults: defaults)
    }

    private static func attempt(accountID: String, delays: [Duration], defaults: UserDefaults) async {
        var remainingDelays = delays[...]
        while true {
            if await send() {
                if defaults.string(forKey: pendingAccountKey) == accountID {
                    defaults.removeObject(forKey: pendingAccountKey)
                }
                return
            }
            guard let delay = remainingDelays.popFirst() else {
                return
            }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, PaeoniaClerk.currentAccountID() == accountID else {
                return
            }
        }
    }

    /// True when the server has stored the answer.
    private static func send() async -> Bool {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return false
        }
        do {
            _ = try await client.action("identity:sync_sign_in_methods") as SignInMethodsSyncResponse
            return true
        } catch {
            return false
        }
    }
}

nonisolated private struct SignInMethodsSyncResponse: Decodable {
    let authProvider: String

    enum CodingKeys: String, CodingKey {
        case authProvider = "auth_provider"
    }
}
