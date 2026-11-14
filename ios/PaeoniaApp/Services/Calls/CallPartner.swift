import Foundation
@preconcurrency import LiveCommunicationKit
import UIKit

/// The partner as calls name them: their user id is the handle in Recents, and the name is what
/// this person calls them (`PartnerName`).
nonisolated struct CallPartner: Equatable, Sendable {
    /// What the system shows instead of the partner's name when lock screen details are private.
    static let privateName = "Paeonia"

    let userID: UUID
    let name: String

    func handle(showsName: Bool) -> Handle {
        Self.handle(userID: userID, name: showsName ? name : Self.privateName)
    }

    static func handle(userID: UUID, name: String) -> Handle {
        Handle(type: .generic, value: userID.uuidString.lowercased(), displayName: name)
    }

    /// The partner from the local store, or nil when signed out, unpaired, or before the first
    /// unlock after a restart, when the store cannot be read.
    @MainActor
    static func current() async -> CallPartner? {
        guard UIApplication.shared.isProtectedDataAvailable,
              let ownerUserID = WidgetSyncIdentityStore.shared.load().currentUserID
        else {
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
