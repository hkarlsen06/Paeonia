import Foundation

/// A time the partners meet in person, from `startDate` to `endDate` (`yyyy-MM-dd`, both
/// included). Each phone reads the days in its own time zone, like `visitPhase` in
/// `backend/convex/lib/visits.ts`.
nonisolated struct Visit: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var startDate: String
    var endDate: String
    var place: MemoryPlace?
    /// When the server last changed it. Nil for a write this phone has not sent yet.
    var updatedAt: String?
    /// Whether this person hid the Us tab card that asks for the visit's photos.
    var memoryPromptDismissed = false

    /// The server refuses more visits that may not be over on some phone, so the phone says so
    /// before queueing one.
    static let maxOpenCount = 20
    /// The days the server accepts for a visit, and its longest span, both days included.
    static let earliestDay = LockScreenCalendarDate(year: 2_000, month: 1, day: 1)
    static let latestDay = LockScreenCalendarDate(year: 2_100, month: 12, day: 31)
    static let maxDays = 366

    enum CodingKeys: String, CodingKey {
        case id
        case startDate = "start_date"
        case endDate = "end_date"
        case place
        case updatedAt = "updated_at"
        case memoryPromptDismissed = "memory_prompt_dismissed"
    }

    enum Phase: Equatable, Sendable {
        /// Whole days until the first day, at least 1.
        case upcoming(days: Int)
        case ongoing
        case ended
    }

    /// Where `today` falls against the visit. Both the first and the last day are ongoing.
    func phase(on today: LockScreenCalendarDate) -> Phase {
        guard let start = LockScreenCalendarDate(startDate), let end = LockScreenCalendarDate(endDate) else {
            return .ended
        }
        if today < start { return .upcoming(days: today.days(until: start)) }
        return today <= end ? .ongoing : .ended
    }

    /// The last day after the editor's first day moved from `oldStart` to `newStart`, so the
    /// visit keeps its length, unless that would put the last day outside the days the server
    /// accepts.
    static func end(
        _ end: Date,
        afterStartMovedFrom oldStart: Date,
        to newStart: Date,
        calendar: Calendar = .current
    ) -> Date {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: oldStart), to: calendar.startOfDay(for: newStart)
        ).day ?? 0
        let moved = calendar.date(byAdding: .day, value: days, to: end) ?? end
        guard let earliest = earliestDay.startOfDay(in: calendar), let latest = latestDay.startOfDay(in: calendar)
        else { return moved }
        return min(max(moved, earliest), latest)
    }
}

/// One thing on the couple's list of things to do together.
nonisolated struct TogetherListItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var isDone: Bool
    /// When the server last changed it. Nil for a write this phone has not sent yet.
    var updatedAt: String?

    /// The server's limit for a trimmed title, in Unicode code points.
    static let maxTitleCodePoints = 80
    /// The server refuses more per couple, ticked ones included.
    static let maxCount = 100

    /// The title the server stores for `text`, or nil when nothing is left after trimming.
    static func title(_ text: String) -> String? {
        let title = ShortTitle.normalized(text, maxCodePoints: maxTitleCodePoints)
        return title.isEmpty ? nil : title
    }
}

/// The couple's visits and their list as this phone knows them.
nonisolated struct CoupleVisits: Codable, Equatable, Sendable {
    var visits: [Visit] = []
    var items: [TogetherListItem] = []

    /// The visit that is ongoing on `today`, or else the soonest upcoming one.
    func currentOrNext(on today: LockScreenCalendarDate) -> Visit? {
        visits
            .filter { $0.phase(on: today) != .ended }
            .min { $0.startDate < $1.startDate }
    }

    /// Whether saving `visit` would make one more visit that may not be over on some phone,
    /// when `Visit.maxOpenCount` already are, like `earliestLocalDate` in
    /// `backend/convex/lib/visits.ts`. No phone's day is before yesterday in UTC.
    func isFull(saving visit: Visit, at now: Date) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let earliest = LockScreenCalendarDate(containing: now.addingTimeInterval(-86_400), in: utc)
        let counts = { (visit: Visit) in LockScreenCalendarDate(visit.endDate).map { $0 >= earliest } ?? false }
        guard counts(visit) else { return false }
        return visits.count { $0.id != visit.id && counts($0) } >= Visit.maxOpenCount
    }

    /// The server's state with this phone's queued writes laid over it, oldest write first,
    /// so an edit shows at once and survives a relaunch while offline.
    func applying(_ writes: [VisitsWrite]) -> CoupleVisits {
        var state = self
        for write in writes {
            state.apply(write)
        }
        return state
    }

    /// What the server stored after a write. A row older than the one already here is left
    /// out, since the live feed may have brought a partner's newer change first. A row the
    /// live feed removed (`removedByFeed`) stays out, since a partner deleted it after the write.
    func confirming(_ confirmation: VisitsConfirmation, removedByFeed: Set<UUID> = []) -> CoupleVisits {
        var state = self
        switch confirmation {
        case let .visit(visit):
            let cached = visits.first { $0.id == visit.id }
            guard cached != nil || !removedByFeed.contains(visit.id) else { break }
            if !Self.isNewer(cached?.updatedAt, than: visit.updatedAt) { state.upsert(visit) }
        case let .visitGone(id):
            state.visits.removeAll { $0.id == id }
        case let .item(item):
            let cached = items.firstIndex { $0.id == item.id }
            if let cached, !Self.isNewer(items[cached].updatedAt, than: item.updatedAt) {
                state.items[cached] = item
            } else if cached == nil, !removedByFeed.contains(item.id) {
                state.items.append(item)
            }
        case let .itemGone(id):
            state.items.removeAll { $0.id == id }
        }
        return state
    }

    /// Server timestamps are ISO 8601 in UTC, so they sort as text.
    private static func isNewer(_ cached: String?, than confirmed: String?) -> Bool {
        guard let cached, let confirmed else { return false }
        return cached > confirmed
    }

    private mutating func apply(_ write: VisitsWrite) {
        switch write {
        case let .saveVisit(payload):
            if let index = visits.firstIndex(where: { $0.id == payload.visit.id }) {
                upsert(payload.applied(to: visits[index]))
            } else {
                upsert(payload.visit)
            }
        case let .deleteVisit(id):
            visits.removeAll { $0.id == id }
        case let .dismissMemoryPrompt(id):
            if let index = visits.firstIndex(where: { $0.id == id }) {
                visits[index].memoryPromptDismissed = true
            }
        case .saveItem, .setItemDone, .deleteItem:
            applyItem(write)
        }
    }

    private mutating func applyItem(_ write: VisitsWrite) {
        switch write {
        case let .saveItem(payload):
            if !items.contains(where: { $0.id == payload.id }) {
                items.append(TogetherListItem(id: payload.id, title: payload.title, isDone: false))
            }
        case let .setItemDone(payload):
            if let index = items.firstIndex(where: { $0.id == payload.id }) {
                items[index].isDone = payload.isDone
            } else {
                items.append(TogetherListItem(id: payload.id, title: payload.title, isDone: payload.isDone))
            }
        case let .deleteItem(id):
            items.removeAll { $0.id == id }
        case .saveVisit, .deleteVisit, .dismissMemoryPrompt:
            break
        }
    }

    private mutating func upsert(_ visit: Visit) {
        if let index = visits.firstIndex(where: { $0.id == visit.id }) {
            visits[index] = visit
        } else {
            visits.append(visit)
        }
        visits.sort { $0.startDate < $1.startDate }
    }
}

/// What the server stored after one write: the row as it is now, or that it is gone.
nonisolated enum VisitsConfirmation: Equatable, Sendable {
    case visit(Visit)
    case visitGone(UUID)
    case item(TogetherListItem)
    case itemGone(UUID)
}

/// A write the server refused for good, kept until the person dismisses the message about it,
/// so they learn about it and keep what they typed.
nonisolated enum VisitsRefusal: Codable, Equatable, Sendable {
    case item(title: String)
    case visit(Visit)
}

/// The result of `visits:get_visits`.
nonisolated struct RemoteCoupleVisits: Decodable, Equatable, Sendable {
    let visits: [Visit]
    let items: [RemoteTogetherItem]

    var state: CoupleVisits {
        CoupleVisits(visits: visits, items: items.map(\.item))
    }
}

/// A list item as the server returns it. Only whether it is ticked matters on the phone.
nonisolated struct RemoteTogetherItem: Decodable, Equatable, Sendable {
    let id: UUID
    let title: String
    let doneAt: String?
    let updatedAt: String

    var item: TogetherListItem {
        TogetherListItem(id: id, title: title, isDone: doneAt != nil, updatedAt: updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case doneAt = "done_at"
        case updatedAt = "updated_at"
    }
}
