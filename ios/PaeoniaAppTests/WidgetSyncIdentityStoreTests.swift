import Foundation
import Testing
@testable import PaeoniaApp

struct WidgetSyncIdentityStoreTests {
    @Test func savesAndLoadsIdentityRoundTrip() {
        let store = makeStore()
        let userID = UUID()

        store.save(
            WidgetSyncIdentity(currentUserID: userID, currentDisplayName: "Me", partnerDisplayName: "Partner")
        )
        let loaded = store.load()

        #expect(loaded.currentUserID == userID)
        #expect(loaded.currentDisplayName == "Me")
        #expect(loaded.partnerDisplayName == "Partner")
    }

    @Test func clearRemovesIdentity() {
        let store = makeStore()
        store.save(
            WidgetSyncIdentity(currentUserID: UUID(), currentDisplayName: "Me", partnerDisplayName: "Partner")
        )

        store.clear()
        let loaded = store.load()

        #expect(loaded.currentUserID == nil)
        #expect(loaded.currentDisplayName == nil)
        #expect(loaded.partnerDisplayName == nil)
    }

    @Test func loadsEmptyIdentityWhenNothingSaved() {
        let loaded = makeStore().load()

        #expect(loaded.currentUserID == nil)
        #expect(loaded.currentDisplayName == nil)
        #expect(loaded.partnerDisplayName == nil)
    }

    private func makeStore() -> WidgetSyncIdentityStore {
        WidgetSyncIdentityStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
    }
}
