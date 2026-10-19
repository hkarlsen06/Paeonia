import Foundation
import Testing
@testable import PaeoniaApp

struct WidgetSyncIdentityStoreTests {
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

    private func makeStore() -> WidgetSyncIdentityStore {
        WidgetSyncIdentityStore(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
    }
}
