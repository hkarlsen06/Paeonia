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

    @Test func lockScreenOnlyWidgetsStillGiveAToken() throws {
        let suiteName = "PaeoniaWidgetPushTokenStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PaeoniaWidgetPushTokenStore(defaults: defaults)
        store.save(token: "token", widgetKinds: [LockScreenWidgetKind.streak])

        #expect(store.loadToken(forWidgetKind: "PaeoniaWidget") == nil)
        #expect(store.loadToken(forAnyOf: ["PaeoniaWidget"] + LockScreenWidgetKind.all) == "token")
        #expect(store.loadToken(forAnyOf: ["OtherWidget"]) == nil)
    }
}
