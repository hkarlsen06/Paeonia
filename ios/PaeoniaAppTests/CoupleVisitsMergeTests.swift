import Foundation
import Testing
@testable import PaeoniaApp

/// Covers how a row the server confirmed after this phone's write merges with the cache,
/// which the live feed may already have moved past.
struct CoupleVisitsMergeTests {
    private let visitID = UUID()
    private let itemID = UUID()

    private func visit(_ start: String, updatedAt: String?) -> Visit {
        Visit(id: visitID, startDate: start, endDate: start, updatedAt: updatedAt)
    }

    private func item(done: Bool, updatedAt: String?) -> TogetherListItem {
        TogetherListItem(id: itemID, title: "Ice skating", isDone: done, updatedAt: updatedAt)
    }

    @Test func aConfirmedRowOlderThanTheFeedsDoesNotReplaceIt() {
        let partnerEdit = visit("2026-11-21", updatedAt: "2026-11-10T12:00:02.000Z")
        let partnerTick = item(done: true, updatedAt: "2026-11-10T12:00:02.000Z")
        let cached = CoupleVisits(visits: [partnerEdit], items: [partnerTick])

        let merged = cached
            .confirming(.visit(visit("2026-11-20", updatedAt: "2026-11-10T12:00:01.000Z")))
            .confirming(.item(item(done: false, updatedAt: "2026-11-10T12:00:01.000Z")))

        #expect(merged == cached)
    }
}
