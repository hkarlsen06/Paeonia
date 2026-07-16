import CryptoKit
import Foundation

/// Remembers that one user has answered the location-sharing explanation for
/// one relationship. The key is relationship-scoped so a new partner gets a
/// fresh, relevant choice, while the stored identifier is hashed so UserDefaults
/// does not expose account or relationship IDs in plaintext.
nonisolated protocol LocationSharingPrimerPersisting {
    func hasResponded(ownerUserID: UUID, coupleID: UUID) -> Bool
    func markResponded(ownerUserID: UUID, coupleID: UUID)
}

nonisolated struct UserDefaultsLocationSharingPrimerStore: LocationSharingPrimerPersisting {
    private static let responseKeyPrefix = "paeonia.location.sharingPrimerResponded.v1."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasResponded(ownerUserID: UUID, coupleID: UUID) -> Bool {
        defaults.bool(forKey: responseKey(ownerUserID: ownerUserID, coupleID: coupleID))
    }

    func markResponded(ownerUserID: UUID, coupleID: UUID) {
        defaults.set(true, forKey: responseKey(ownerUserID: ownerUserID, coupleID: coupleID))
    }

    private func responseKey(ownerUserID: UUID, coupleID: UUID) -> String {
        let relationshipIdentity = [
            ownerUserID.uuidString.lowercased(),
            coupleID.uuidString.lowercased(),
        ].joined(separator: ":")
        let digest = SHA256.hash(data: Data(relationshipIdentity.utf8))
        let digestString = digest.map { String(format: "%02x", $0) }.joined()
        return Self.responseKeyPrefix + digestString
    }
}
