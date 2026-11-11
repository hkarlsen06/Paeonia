import Foundation

/// What the Us tab's visit card shows on one day (`HomeVisitCard`).
nonisolated enum HomeVisitCardState: Equatable, Sendable {
    /// Nothing: the cache isn't read yet, or the person hid the question.
    case hidden
    /// "When do you meet next?"
    case prompt
    /// The next visit, which has not started yet.
    case visit(Visit)
    /// The partners are together today. During a visit, `until` is the last day of the visits
    /// in a row that hold today, overlapping or back to back, where the server's together run
    /// ends too, and `place` is the place of the latest one that has started. When only their
    /// phones showed them together, both are nil.
    case together(until: LockScreenCalendarDate?, place: MemoryPlace?)

    /// `restsTogether` is whether the streak rests today (`StreakPillState.restsWhileTogether`).
    init(
        visits: CoupleVisits,
        on today: LockScreenCalendarDate,
        restsTogether: Bool,
        promptReturnDay: LockScreenCalendarDate?
    ) {
        let dated = visits.visits.compactMap(DatedVisit.init)
        let holding = dated.filter { $0.start <= today && today <= $0.end }
        if let latest = holding.max(by: { $0.start < $1.start }), var until = holding.map(\.end).max() {
            while let next = dated.filter({ $0.start.days(until: until) >= -1 && $0.end > until }).map(\.end).max() {
                until = next
            }
            self = .together(until: until, place: latest.visit.place)
        } else if restsTogether {
            self = .together(until: nil, place: nil)
        } else if let next = visits.currentOrNext(on: today) {
            self = .visit(next)
        } else {
            self = promptReturnDay.map { today < $0 } == true ? .hidden : .prompt
        }
    }
}

nonisolated private struct DatedVisit {
    let visit: Visit
    let start: LockScreenCalendarDate
    let end: LockScreenCalendarDate

    init?(_ visit: Visit) {
        guard let start = LockScreenCalendarDate(visit.startDate),
              let end = LockScreenCalendarDate(visit.endDate)
        else { return nil }
        self.visit = visit
        self.start = start
        self.end = end
    }
}
