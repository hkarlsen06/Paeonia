import Foundation
import Testing
@testable import PaeoniaApp

struct PaeoniaWidgetPushTokenStoreTests {
    @Test func saveTokenDataAsHexAndFiltersByWidgetKind() throws {
        let suiteName = "PaeoniaWidgetPushTokenStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PaeoniaWidgetPushTokenStore(defaults: defaults)
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.save(
            tokenData: Data([0x00, 0x0f, 0xff]),
            widgetKinds: ["PaeoniaWidget", "PaeoniaWidget"],
            savedAt: savedAt
        )

        #expect(store.load() == PaeoniaWidgetPushTokenSnapshot(
            token: "000fff",
            widgetKinds: ["PaeoniaWidget"],
            savedAt: savedAt
        ))
        #expect(store.loadToken(forWidgetKind: "PaeoniaWidget") == "000fff")
        #expect(store.loadToken(forWidgetKind: "OtherWidget") == nil)
    }

    @Test func emptyWidgetKindListDoesNotReturnStaleTokenForRegistration() throws {
        let suiteName = "PaeoniaWidgetPushTokenStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PaeoniaWidgetPushTokenStore(defaults: defaults)
        store.save(token: "token", widgetKinds: [])

        #expect(store.loadToken(forWidgetKind: "PaeoniaWidget") == nil)
    }

    @Test func nilDefaultsFallbackCanPersistToken() {
        let defaults = UserDefaults.standard
        let keys = [
            "paeonia.widgetPush.token",
            "paeonia.widgetPush.widgetKinds",
            "paeonia.widgetPush.savedAt",
        ]
        keys.forEach(defaults.removeObject)
        defer {
            keys.forEach(defaults.removeObject)
        }

        let store = PaeoniaWidgetPushTokenStore(defaults: nil)
        let savedAt = Date(timeIntervalSince1970: 1_800_000_001)

        store.save(token: "fallback-token", widgetKinds: ["PaeoniaWidget"], savedAt: savedAt)

        #expect(store.load() == PaeoniaWidgetPushTokenSnapshot(
            token: "fallback-token",
            widgetKinds: ["PaeoniaWidget"],
            savedAt: savedAt
        ))
    }
}
