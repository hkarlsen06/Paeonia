import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SyncClientOperationFactoryTests {
    @Test func factoryReusesClientIDAndIncrementsSequence() throws {
        let defaults = try makeDefaults()
        let factory = SyncClientOperationFactory(defaults: defaults)

        let firstOperation = factory.makeOperation()
        let secondOperation = factory.makeOperation()

        #expect(firstOperation.id != secondOperation.id)
        #expect(firstOperation.clientID == secondOperation.clientID)
        #expect(secondOperation.clientSequence == firstOperation.clientSequence + 1)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "no.paeonia.tests.sync-client-operation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
