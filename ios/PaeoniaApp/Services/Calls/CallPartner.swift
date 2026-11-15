import Foundation
@preconcurrency import LiveCommunicationKit
import UIKit

/// The partner as calls name them: the name is what this person calls them (`PartnerName`).
nonisolated struct CallPartner: Equatable, Sendable {
    /// What the system shows instead of the partner's name when lock screen details are private.
    static let privateName = "Paeonia"

    let userID: UUID
    let name: String

    func handle(showsName: Bool) -> Handle {
        Self.handle(name: showsName ? name : Self.privateName)
    }

    /// The system call UI shows a handle's value and ignores its display name (FB24933340), so
    /// the value is the name the call shows. Recents and Siri hand that name back for a call back.
    static func handle(name: String) -> Handle {
        Handle(type: .generic, value: name, displayName: name)
    }

    /// Whether a call back from Recents or Siri, which hands back the name a call showed, calls
    /// this partner. A couple has one partner, so their current name and "Paeonia" both do.
    func answersCallBack(to handleValue: String) -> Bool {
        handleValue == name || handleValue == Self.privateName
    }

    /// The partner from the local store, or nil when signed out or unpaired. A locked phone
    /// cannot read the store, so it gets the partner from the last read instead (`cached`).
    @MainActor
    static func current() async -> CallPartner? {
        guard UIApplication.shared.isProtectedDataAvailable else {
            return cached
        }
        let partner = await fromStore()
        cache(partner)
        return partner
    }

    @MainActor
    private static func fromStore() async -> CallPartner? {
        guard let ownerUserID = WidgetSyncIdentityStore.shared.load().currentUserID else {
            return nil
        }
        let store = SwiftDataAccessSyncSnapshotRepository(container: PaeoniaLocalStore.shared.container)
        guard let relationship = try? await store.load(ownerUserID: ownerUserID)?.relationshipState,
              let partnerUserID = relationship.partnerUserID
        else {
            return nil
        }
        return CallPartner(userID: partnerUserID, name: relationship.partnerName.displayOrFallback)
    }
}

/// The partner from the last read of the store, so a call can ring with their name on a locked
/// phone. UserDefaults stays readable after the first unlock. The privacy purge clears it.
nonisolated extension CallPartner {
    private static let cacheKey = "paeonia.calls.partner"
    private static let userIDKey = "user_id"
    private static let nameKey = "name"

    static var cached: CallPartner? {
        guard let stored = UserDefaults.standard.dictionary(forKey: cacheKey),
              let userID = (stored[userIDKey] as? String).flatMap(UUID.init(uuidString:)),
              let name = stored[nameKey] as? String
        else {
            return nil
        }
        return CallPartner(userID: userID, name: name)
    }

    static func cache(_ partner: CallPartner?) {
        guard let partner else {
            clearCache()
            return
        }
        UserDefaults.standard.set(
            [userIDKey: partner.userID.uuidString, nameKey: partner.name],
            forKey: cacheKey
        )
    }

    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
