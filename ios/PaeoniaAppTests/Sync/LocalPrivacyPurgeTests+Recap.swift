import Foundation
import Testing
@testable import PaeoniaApp

extension LocalPrivacyPurgeTests {
    @Test(arguments: everyPurgeScope)
    func everyPurgeRemovesTheRecaps(scope: LocalPrivacyPurgeScope) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileRecapCache(directoryURL: directory.appendingPathComponent("recap"))
        let owner = UUID(), coupleID = UUID()
        let entry = RecapCacheEntry(coupleID: coupleID, recaps: [Self.recap])
        let readBeforePurge = cache.purgeCount()
        #expect(cache.save(entry, ownerUserID: owner, unlessPurgedSince: readBeforePurge))
        let fixture = try LivePurgeFixture(widgetCanvas: WidgetCanvasTestEnvironment().makeService(),
                                           memoryMediaURL: directory.appendingPathComponent("memory"),
                                           recapCache: cache)

        #expect(await fixture.purger.purge(ownerUserID: owner, scope: scope) == .completed)

        #expect(cache.load(ownerUserID: owner, coupleID: coupleID) == nil)
        // A read that started before the purge does not bring the numbers back.
        #expect(!cache.save(entry, ownerUserID: owner, unlessPurgedSince: readBeforePurge))
        #expect(cache.load(ownerUserID: owner, coupleID: coupleID) == nil)
    }

    private static let recap = AnniversaryRecap(
        anniversaryDate: "2026-11-11", years: 1, periodStart: "2025-11-11", periodEnd: "2026-11-11",
        sinceJoined: false, countedOn: "2026-11-12",
        counts: .init(
            answeredTogether: 3, drawings: 0, memories: 0, memoryPhotos: 0, stories: 0, letters: 0, visits: 0,
            visitDays: 0, gameDays: 0, heartsAllTime: 0, longestStreakAllTime: 0
        )
    )
}
