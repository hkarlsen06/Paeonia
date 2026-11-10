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

    /// The server refuses more visits that are not over, so the phone says so before queueing one.
    static let maxOpenCount = 20

    enum CodingKeys: String, CodingKey {
        case id
        case startDate = "start_date"
        case endDate = "end_date"
        case place
        case updatedAt = "updated_at"
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
    /// visit keeps its length.
    static func end(
        _ end: Date,
        afterStartMovedFrom oldStart: Date,
        to newStart: Date,
        calendar: Calendar = .current
    ) -> Date {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: oldStart), to: calendar.startOfDay(for: newStart)
        ).day ?? 0
        return calendar.date(byAdding: .day, value: days, to: end) ?? end
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

    /// Whether saving `visit` would make one more visit that is not over, when
    /// `Visit.maxOpenCount` already are. The server checks the same on its day.
    func isFull(saving visit: Visit, on today: LockScreenCalendarDate) -> Bool {
        let isOpen = { (visit: Visit) in visit.phase(on: today) != .ended }
        let wasOpen = visits.first { $0.id == visit.id }.map(isOpen) ?? false
        guard !wasOpen, isOpen(visit) else { return false }
        return visits.count { $0.id != visit.id && isOpen($0) } >= Visit.maxOpenCount
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
    /// out, since the live feed may have brought a partner's newer change first.
    func confirming(_ confirmation: VisitsConfirmation) -> CoupleVisits {
        var state = self
        switch confirmation {
        case let .visit(visit):
            let cached = visits.first { $0.id == visit.id }
            if !Self.isNewer(cached?.updatedAt, than: visit.updatedAt) { state.upsert(visit) }
        case let .visitGone(id):
            state.visits.removeAll { $0.id == id }
        case let .item(item):
            let cached = items.firstIndex { $0.id == item.id }
            if let cached, !Self.isNewer(items[cached].updatedAt, than: item.updatedAt) {
                state.items[cached] = item
            } else if cached == nil {
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
        case let .saveVisit(visit):
            upsert(visit)
        case let .deleteVisit(id):
            visits.removeAll { $0.id == id }
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

/// A write the server refused for good, kept until a screen shows it, so the person learns
/// about it and keeps what they typed.
nonisolated enum VisitsRefusal: Codable, Equatable, Sendable {
    case item(title: String)
    case visit(Visit)
}

/// One queued write, decoded from its pending operation.
nonisolated enum VisitsWrite: Equatable, Sendable {
    case saveVisit(Visit)
    case deleteVisit(UUID)
    case saveItem(SaveTogetherItemPayload)
    case setItemDone(SetTogetherItemDonePayload)
    case deleteItem(UUID)

    init?(_ operation: PendingSyncOperationSnapshot) {
        guard let data = operation.requestData, let kind = operation.operationKind else { return nil }
        let write: Self? = switch kind {
        case .saveVisit: Self.decode(Visit.self, data).map(Self.saveVisit)
        case .deleteVisit: Self.decode(VisitIDPayload.self, data).map { .deleteVisit($0.id) }
        case .saveTogetherItem: Self.decode(SaveTogetherItemPayload.self, data).map(Self.saveItem)
        case .setTogetherItemDone: Self.decode(SetTogetherItemDonePayload.self, data).map(Self.setItemDone)
        case .deleteTogetherItem: Self.decode(VisitIDPayload.self, data).map { .deleteItem($0.id) }
        default: nil
        }
        guard let write else { return nil }
        self = write
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    static let operationKinds: [SyncPendingOperationKind] = [
        .saveVisit, .deleteVisit, .saveTogetherItem, .setTogetherItemDone, .deleteTogetherItem,
    ]

    /// What the person loses when the server refuses this write for good. Nil for a delete.
    var refusal: VisitsRefusal? {
        switch self {
        case let .saveVisit(visit): .visit(visit)
        case let .saveItem(payload): .item(title: payload.title)
        case let .setItemDone(payload): .item(title: payload.title)
        case .deleteVisit, .deleteItem: nil
        }
    }
}

/// `visits:delete_visit` and `visits:delete_together_item`.
nonisolated struct VisitIDPayload: Codable, Equatable, Sendable {
    let id: UUID
}

/// `visits:save_together_item`.
nonisolated struct SaveTogetherItemPayload: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
}

/// `visits:set_together_item_done`. It carries the title, because it adds the item when it
/// reaches the server before the item's add.
nonisolated struct SetTogetherItemDonePayload: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let isDone: Bool
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
