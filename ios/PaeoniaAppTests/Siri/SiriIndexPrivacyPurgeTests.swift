import Foundation
import Testing
@testable import PaeoniaApp

/// Spotlight and Siri must forget the couple's dates, memories and photos on sign-out, account
/// deletion, leaving, and a temporary loss of access alike, through the central purge.
struct SiriIndexPrivacyPurgeTests {
    @Test(arguments: LocalPrivacyPurgeTests.everyPurgeScope)
    func everyPurgeRemovesTheCouplesContentFromSpotlight(scope: LocalPrivacyPurgeScope) async throws {
        let spotlight = FakeSpotlightIndex(indexed: ["countdown:trip", "birthday:partner", "memory:bergen", "photo:1"])
        let fixture = try PurgeFixture(spotlight: spotlight)
        defer { fixture.removeDefaults() }

        #expect(await fixture.purger.purge(ownerUserID: UUID(), scope: scope) == .completed)

        #expect(await spotlight.indexed.isEmpty)
    }

    @Test(arguments: LocalPrivacyPurgeTests.everyPurgeScope)
    @MainActor
    func everyPurgeRemovesTheMessageWaitingInSiri(scope: LocalPrivacyPurgeScope) async throws {
        let fixture = try PurgeFixture(spotlight: FakeSpotlightIndex(indexed: []))
        defer { fixture.removeDefaults() }
        let owner = UUID()
        SiriAppContext.shared.messageDraft = SiriMessageDraft(ownerUserID: owner, subject: .couple, body: "Private")
        #expect(await fixture.purger.purge(ownerUserID: owner, scope: scope) == .completed)
        #expect(SiriAppContext.shared.messageDraft == nil)
    }

    @Test func aSpotlightRemovalThatFailsStaysQueuedUntilARetryClearsIt() async throws {
        let ownerUserID = UUID()
        let spotlight = FakeSpotlightIndex(indexed: ["memory:bergen"], failuresBeforeSuccess: 1)
        let fixture = try PurgeFixture(spotlight: spotlight)
        defer { fixture.removeDefaults() }

        #expect(await fixture.purger.purge(ownerUserID: ownerUserID, scope: .departingUser) == .recordsPendingRetry)
        #expect(await spotlight.indexed == ["memory:bergen"])
        #expect(try await fixture.retryStore.request(for: ownerUserID) != nil)

        #expect(await fixture.purger.retryPendingPurges() == .completed)
        #expect(await spotlight.indexed.isEmpty)
        #expect(try await fixture.retryStore.request(for: ownerUserID) == nil)
    }
}

/// The real purge service, record store and retry ledger, with Spotlight faked at the OS boundary.
private struct PurgeFixture {
    let purger: LocalPrivacyPurgeService
    let retryStore: UserDefaultsLocalPrivacyPurgeRetryStore
    private let suiteName = "SiriIndexPrivacyPurgeTests.\(UUID().uuidString)"

    init(spotlight: FakeSpotlightIndex) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        retryStore = UserDefaultsLocalPrivacyPurgeRetryStore(defaults: defaults)
        purger = LocalPrivacyPurgeService(
            recordStore: SwiftDataLocalPrivacyRecordStore(container: try PaeoniaLocalStore(inMemory: true).container),
            privateContentPurger: NoPrivateFiles(),
            entityIndex: spotlight,
            retryStore: retryStore,
            automaticallyRetry: false
        )
    }

    func removeDefaults() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

private struct NoPrivateFiles: LocalPrivateContentPurging {
    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) {}
}
