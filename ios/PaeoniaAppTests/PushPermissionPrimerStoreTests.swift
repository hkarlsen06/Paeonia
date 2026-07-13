import Foundation
import Testing
@testable import PaeoniaApp

struct PushPermissionPrimerStoreTests {
    @Test func freshInstallationHasNotResponded() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }

        let store = UserDefaultsPushPermissionPrimerStore(defaults: environment.defaults)

        #expect(!store.hasResponded())
    }

    @Test func responsePersistsAcrossStoreInstances() throws {
        let environment = try makeEnvironment()
        defer { environment.defaults.removePersistentDomain(forName: environment.suiteName) }
        let firstStore = UserDefaultsPushPermissionPrimerStore(defaults: environment.defaults)

        firstStore.markResponded()

        let restoredStore = UserDefaultsPushPermissionPrimerStore(defaults: environment.defaults)
        #expect(restoredStore.hasResponded())
    }

    private func makeEnvironment() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "PushPermissionPrimerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
