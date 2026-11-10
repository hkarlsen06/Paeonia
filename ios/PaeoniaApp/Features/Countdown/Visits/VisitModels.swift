import Foundation

/// A time the partners meet in person, from `startDate` to `endDate` (`yyyy-MM-dd`, both
/// included). Each phone reads the days in its own time zone, like `visitPhase` in
/// `backend/convex/lib/visits.ts`.
nonisolated struct Visit: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var startDate: String
    var endDate: String
    var place: MemoryPlace?

    /// The server refuses more per couple, so the phone says so before queueing one.
    static let maxCount = 20

    enum CodingKeys: String, CodingKey {
        case id
        case startDate = "start_date"
        case endDate = "end_date"
        case place
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
}

/// One thing on the couple's list of things to do together.
nonisolated struct TogetherListItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var isDone: Bool

    /// The add field caps titles at this many characters.
    static let maxTitleLength = 40
    /// The server refuses more per couple, ticked ones included.
    static let maxCount = 100
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

    /// The server's state with this phone's queued writes laid over it, oldest write first,
    /// so an edit shows at once and survives a relaunch while offline.
    func applying(_ writes: [VisitsWrite]) -> CoupleVisits {
        var state = self
        for write in writes {
            state.apply(write)
        }
        return state
    }

    private mutating func apply(_ write: VisitsWrite) {
        switch write {
        case let .saveVisit(visit):
            upsert(visit)
        case let .deleteVisit(id):
            visits.removeAll { $0.id == id }
        case let .saveItem(payload):
            if let index = items.firstIndex(where: { $0.id == payload.id }) {
                items[index].title = payload.title
            } else {
                items.append(TogetherListItem(id: payload.id, title: payload.title, isDone: false))
            }
        case let .setItemDone(payload):
            if let index = items.firstIndex(where: { $0.id == payload.id }) {
                items[index].isDone = payload.isDone
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

/// `visits:set_together_item_done`.
nonisolated struct SetTogetherItemDonePayload: Codable, Equatable, Sendable {
    let id: UUID
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

    var item: TogetherListItem {
        TogetherListItem(id: id, title: title, isDone: doneAt != nil)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case doneAt = "done_at"
    }
}
