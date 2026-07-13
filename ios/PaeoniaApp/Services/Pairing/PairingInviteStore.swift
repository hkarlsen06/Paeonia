import Foundation

@MainActor
protocol PairingInviteStoring: AnyObject {
    func loadInvite(for userID: String) -> PairingInvite?
    func saveInvite(_ invite: PairingInvite, for userID: String)
    func clearInvite(for userID: String)
}

@MainActor
final class UserDefaultsPairingInviteStore: PairingInviteStoring {
    static let shared = UserDefaultsPairingInviteStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        guard let data = defaults.data(forKey: key(for: userID)),
              let storedInvite = try? JSONDecoder().decode(StoredPairingInvite.self, from: data),
              storedInvite.expiresAt > Date()
        else {
            clearInvite(for: userID)
            return nil
        }

        return storedInvite.invite
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        let storedInvite = StoredPairingInvite(invite: invite)
        guard let data = try? JSONEncoder().encode(storedInvite) else {
            return
        }

        defaults.set(data, forKey: key(for: userID))
    }

    func clearInvite(for userID: String) {
        let variants = [
            userID,
            UUID(uuidString: userID)?.uuidString,
            UUID(uuidString: userID)?.uuidString.lowercased(),
        ]
        for variant in Set(variants.compactMap { $0 }) {
            defaults.removeObject(forKey: key(for: variant))
        }
    }

    private func key(for userID: String) -> String {
        "paeonia.pairing.invite.\(userID)"
    }
}

private struct StoredPairingInvite: Codable {
    let id: UUID
    let code: String
    let joinURL: URL
    let expiresAt: Date

    init(invite: PairingInvite) {
        self.id = invite.id
        self.code = invite.code
        self.joinURL = invite.joinURL
        self.expiresAt = invite.expiresAt
    }

    var invite: PairingInvite {
        PairingInvite(
            id: id,
            code: code,
            joinURL: joinURL,
            expiresAt: expiresAt
        )
    }
}
