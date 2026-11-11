import Foundation
import Testing
@testable import PaeoniaApp

/// Covers how a row the server confirmed after this phone's write merges with the cache,
/// which the live feed may already have moved past, what a visit save sends, and when the
/// phone counts a visit toward the cap.
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

    @Test func aConfirmedRowThePartnerDeletedAfterTheWriteStaysDeleted() async {
        let owner = UUID()
        let cache = InMemoryVisitsCache()
        let ice = item(done: false, updatedAt: "2026-11-10T12:00:01.000Z")
        let cached = CoupleVisits(visits: [visit("2026-11-20", updatedAt: "2026-11-10T12:00:01.000Z")], items: [ice])
        await cache.save(cached, ownerUserID: owner)
        // The live feed shows the partner's deletes before this phone's edit and tick are confirmed.
        await cache.save(CoupleVisits(), ownerUserID: owner)
        await cache.confirm(.visit(visit("2026-11-21", updatedAt: "2026-11-10T12:00:02.000Z")), ownerUserID: owner)
        await cache.confirm(.item(item(done: true, updatedAt: "2026-11-10T12:00:02.000Z")), ownerUserID: owner)

        #expect(await cache.state(ownerUserID: owner).visits == CoupleVisits())

        let planned = Visit(
            id: UUID(), startDate: "2026-12-01", endDate: "2026-12-02", updatedAt: "2026-11-10T12:00:03.000Z"
        )
        await cache.confirm(.visit(planned), ownerUserID: owner)
        #expect(await cache.state(ownerUserID: owner).visits.visits == [planned])
    }

    @Test func aVisitEditSendsTheFieldsThatDifferFromTheServerOrThatAQueuedSaveChanges() {
        let bergen = MemoryPlace(name: "Bryggen", latitude: 60.397, longitude: 5.324, city: "Bergen", countryCode: "NO")
        let server = Visit(id: visitID, startDate: "2026-11-20", endDate: "2026-11-23", place: bergen)
        var moved = server
        moved.endDate = "2026-11-25"

        #expect(SaveVisitPayload(moved, server: nil, pending: []).changes == [.startDate, .endDate, .place])
        #expect(SaveVisitPayload(moved, server: server, pending: []).changes == [.endDate])

        var placeless = server
        placeless.place = nil
        let queued = VisitsWrite.saveVisit(SaveVisitPayload(placeless, server: server, pending: []))
        var movedBack = placeless
        movedBack.place = bergen
        #expect(SaveVisitPayload(movedBack, server: server, pending: [queued]).changes == [.place])

        // A partner moved the first day. This phone's edit of the last day keeps it.
        var partnerMoved = server
        partnerMoved.startDate = "2026-11-19"
        let merged = CoupleVisits(visits: [partnerMoved])
            .applying([.saveVisit(SaveVisitPayload(moved, server: server, pending: []))])
        #expect(merged.visits.first?.startDate == "2026-11-19")
        #expect(merged.visits.first?.endDate == "2026-11-25")
    }

    @Test func aVisitCountsTowardTheCapUntilItsLastDayIsOverOnEveryPhone() throws {
        let open = (0..<(Visit.maxOpenCount - 1)).map { _ in
            Visit(id: UUID(), startDate: "2026-12-01", endDate: "2026-12-02")
        }
        let endedYesterdayInUTC = Visit(id: UUID(), startDate: "2026-10-08", endDate: "2026-10-09")
        let visits = CoupleVisits(visits: open + [endedYesterdayInUTC])
        let new = Visit(id: UUID(), startDate: "2026-12-10", endDate: "2026-12-11")

        // 23:00 UTC on 10 October is still 9 October in UTC-12.
        let lateOnTheTenth = try #require(ISO8601DateFormatter().date(from: "2026-10-10T23:00:00Z"))
        #expect(visits.isFull(saving: new, at: lateOnTheTenth))
        #expect(!visits.isFull(saving: new, at: lateOnTheTenth.addingTimeInterval(3_600)))
        #expect(!visits.isFull(saving: endedYesterdayInUTC, at: lateOnTheTenth))
    }

    @Test func aQueuedTickAddsAnItemWhoseAddHasNotArrived() {
        let tick = SetTogetherItemDonePayload(id: itemID, title: "Ice skating", isDone: true)
        let other = item(done: false, updatedAt: "2026-11-10T12:00:01.000Z")
        let ticked = CoupleVisits().applying([.setItemDone(tick)])

        #expect(ticked.items == [TogetherListItem(id: itemID, title: "Ice skating", isDone: true)])
        // A tick of an item already here only ticks it.
        #expect(CoupleVisits(items: [other]).applying([.setItemDone(tick)]).items.map(\.isDone) == [true])
    }
}
