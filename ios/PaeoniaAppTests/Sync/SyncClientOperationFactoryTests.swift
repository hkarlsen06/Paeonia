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

    @Test func factoryMigratesLegacyPairingDefaults() throws {
        let defaults = try makeDefaults()
        let legacyClientID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        defaults.set(legacyClientID.uuidString, forKey: "paeonia.pairing.clientID")
        defaults.set(41, forKey: "paeonia.pairing.clientSequence")

        let factory = SyncClientOperationFactory(defaults: defaults)
        let operation = factory.makeOperation()
        let nextOperation = factory.makeOperation()

        #expect(operation.clientID == legacyClientID)
        #expect(operation.clientSequence == 42)
        #expect(nextOperation.clientSequence == 43)
    }

    @Test func factoryContinuesFromHighestLegacySequence() throws {
        let defaults = try makeDefaults()
        let legacyClientID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        defaults.set(legacyClientID.uuidString, forKey: "paeonia.auth.clientID")
        defaults.set(11, forKey: "paeonia.pairing.clientSequence")
        defaults.set(41, forKey: "paeonia.auth.clientSequence")
        defaults.set(19, forKey: "paeonia.widgetCanvas.clientSequence")

        let factory = SyncClientOperationFactory(defaults: defaults)
        let operation = factory.makeOperation()

        #expect(operation.clientID == legacyClientID)
        #expect(operation.clientSequence == 42)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "no.paeonia.tests.sync-client-operation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
