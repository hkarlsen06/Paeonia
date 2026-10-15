import Testing
@testable import PaeoniaApp

struct DraftWriteOrderTests {
    @Test func theLatestTicketWrites() {
        let order = DraftWriteOrder()
        var written: [Int] = []
        let ticket = order.nextTicket()

        order.perform(ticket) { written.append(ticket) }

        #expect(written == [ticket])
    }

    @Test func anEarlierTicketIsSkippedOnceALaterOneExists() {
        let order = DraftWriteOrder()
        var written: [Int] = []
        let earlier = order.nextTicket()
        let later = order.nextTicket()

        order.perform(later) { written.append(later) }
        order.perform(earlier) { written.append(earlier) }

        #expect(written == [later])
    }

    @Test func aWriteRightAwayMakesAnEarlierTicketStale() {
        let order = DraftWriteOrder()
        var written: [String] = []
        let ticket = order.nextTicket()

        order.performNow { written.append("now") }
        order.perform(ticket) { written.append("late") }

        #expect(written == ["now"])
    }
}
